defmodule Example.Siem do
  @moduledoc """
  The example's consumer of the library's two events: a process that maps
  every change event and every decision event to an OCSF record and holds
  the result in memory.

  A deployment sends those records to its security log. Holding them in a
  list keeps the mapping under test without putting a schema version in a
  published package, which is the division `Example.Siem.Ocsf` describes.
  Records arrive as casts and are read as calls, so a caller that caused
  an event reads its own records afterwards. The thin application starts
  one at boot; a test starts its own, unattached, and feeds it payloads.
  """

  use GenServer

  alias Example.Siem.Ocsf
  alias Turnstile.Port
  alias Turnstile.Repo.Change

  @schema NimbleOptions.new!(
            name: [type: :any, doc: "A registered name, or none."],
            attach: [type: :boolean, default: false, doc: "Attach to the library's two events."]
          )

  @doc "Start the consumer. Options: #{NimbleOptions.docs(@schema)}"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    opts = NimbleOptions.validate!(opts, @schema)

    case opts[:name] do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "The events it attaches to: the change event and the decision event."
  @spec events() :: [[atom()]]
  def events, do: [Change.event(), Port.event()]

  @doc "Every record it holds, oldest first."
  @spec records(GenServer.server()) :: [map()]
  def records(siem), do: GenServer.call(siem, :records)

  @doc "The records of one operation, oldest first."
  @spec records(GenServer.server(), String.t()) :: [map()]
  def records(siem, operation_id) when is_binary(operation_id) do
    siem
    |> records()
    |> Enum.filter(&(&1.metadata.correlation_uid == operation_id))
  end

  @doc "Hold one record; what the telemetry handler does with what it mapped."
  @spec record(GenServer.server(), map()) :: :ok
  def record(siem, record) when is_map(record), do: GenServer.cast(siem, {:record, record})

  @doc false
  @spec handle_event([atom()], map(), map(), GenServer.server()) :: :ok
  def handle_event([:turnstile, :change], _measurements, payload, siem) do
    record(siem, Ocsf.change(payload))
  end

  def handle_event([:turnstile, :decision], _measurements, %{verdict: nil}, _siem), do: :ok

  def handle_event([:turnstile, :decision], %{duration: duration}, metadata, siem) do
    record(siem, Ocsf.decision(metadata, duration))
  end

  @impl GenServer
  def init(opts) do
    if opts[:attach] do
      Process.flag(:trap_exit, true)
      :ok = :telemetry.attach_many(handler_id(), events(), &__MODULE__.handle_event/4, self())
    end

    {:ok, %{records: [], attached: opts[:attach]}}
  end

  @impl GenServer
  def handle_cast({:record, record}, state), do: {:noreply, %{state | records: [record | state.records]}}

  @impl GenServer
  def handle_call(:records, _from, state), do: {:reply, Enum.reverse(state.records), state}

  @impl GenServer
  def terminate(_reason, %{attached: true}), do: :telemetry.detach(handler_id())
  def terminate(_reason, _state), do: :ok

  defp handler_id, do: {__MODULE__, self()}
end

defmodule Example.Siem.Ocsf do
  @moduledoc """
  The mapping from the library's two events to OCSF records, against
  schema version 1.3.0.

  The library carries the meaning and this module carries the format. The
  class, category, severity, and type identifiers, the product metadata,
  and the shape of the actor are the consumer's, because each of them
  depends on the schema version it targets and the identifiers move
  between versions. A change event's kind gives the class and its
  operation the activity, numbered as Entity Management numbers create,
  update, and delete. A decision is an API activity whose verdict is the
  status and whose operation is the one asked about, or `Other` where
  OCSF numbers none. What OCSF does not name travels under `unmapped`,
  which is where OCSF says to put it.
  """

  @version "1.3.0"
  @product %{name: "Example", vendor_name: "Turnstile"}

  @classes %{
    user: {3, 3001, "Account Change"},
    group: {3, 3006, "Group Management"},
    role: {3, 3005, "User Access Management"},
    entity: {3, 3004, "Entity Management"}
  }

  @operations %{create: {1, "Create"}, update: {3, "Update"}, delete: {4, "Delete"}}
  @asked %{create: {1, "Create"}, read: {2, "Read"}, update: {3, "Update"}, delete: {4, "Delete"}}
  @other {99, "Other"}
  @api {6, 6003, "API Activity"}

  @users %{user: {1, "User"}, privileged: {2, "Admin"}, non_person_entity: {3, "System"}}
  @unknown_user {0, "Unknown"}

  @doc "The schema version this mapping targets."
  @spec version() :: String.t()
  def version, do: @version

  @doc "A change event as the record of a managed entity that changed."
  @spec change(map()) :: map()
  def change(payload) when is_map(payload) do
    {category, class, name} = Map.fetch!(@classes, payload.kind)
    {activity, activity_name} = Map.fetch!(@operations, payload.operation)

    %{
      category_uid: category,
      class_uid: class,
      class_name: name,
      activity_id: activity,
      activity_name: activity_name,
      type_uid: class * 100 + activity,
      severity_id: 1,
      time: payload.time,
      actor: actor(payload.actor, payload.actor_kind),
      entity: reference(payload.target),
      metadata: metadata(payload.operation_id),
      unmapped: %{changes: changes(payload.changes), schema: inspect(payload.schema)}
    }
  end

  @doc "A decision event as the record of an API activity, with its duration in microseconds."
  @spec decision(map(), non_neg_integer()) :: map()
  def decision(said, duration) when is_map(said) and is_integer(duration) do
    {category, class, name} = @api
    {activity, activity_name} = Map.get(@asked, said.operation, @other)

    record = %{
      category_uid: category,
      class_uid: class,
      class_name: name,
      activity_id: activity,
      activity_name: activity_name,
      type_uid: class * 100 + activity,
      time: said.time,
      duration: duration,
      actor: actor(said.subject, said.subject_kind),
      resource: reference(said.object),
      api: %{operation: Atom.to_string(said.operation), response: %{message: text(said.reason)}},
      metadata: metadata(said.operation_id),
      unmapped: asked(said)
    }

    Map.merge(record, outcome(said.verdict))
  end

  # A verdict is a status and a severity, which is what a security log
  # sorts and alerts on.
  defp outcome(:allow), do: %{status_id: 1, status: "Success", severity_id: 1}
  defp outcome(:deny), do: %{status_id: 2, status: "Failure", severity_id: 2}

  # What OCSF names no field for: which decider answered, under which
  # version of its rules, from which facts, and what it raised.
  defp asked(said) do
    %{
      decider: inspect(said.decider),
      policy_version: said.version,
      env: said.env,
      exception: exception(said.exception)
    }
  end

  defp metadata(operation_id) do
    %{version: @version, product: @product, correlation_uid: operation_id}
  end

  defp actor({_kind, id}, kind) do
    {type, type_name} = Map.get(@users, kind, @unknown_user)

    %{user: %{uid: identifier(id), type_id: type, type: type_name}}
  end

  # A narrowing call answers about a query rather than a row, and the query
  # is a rule over attribute values, which no record of this example carries.
  defp reference({type, id}) when is_atom(type), do: %{type: text(type), uid: identifier(id)}
  defp reference(_query), do: %{type: "query", uid: nil}

  defp changes(changes) do
    Map.new(changes, fn {field, {old, new}} -> {field, %{before: old, after: new}} end)
  end

  defp exception(nil), do: nil
  defp exception(exception), do: inspect(exception.__struct__)

  defp text(nil), do: nil
  defp text(atom), do: Atom.to_string(atom)

  defp identifier(nil), do: nil
  defp identifier(id), do: to_string(id)
end
