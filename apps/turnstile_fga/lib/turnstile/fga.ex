defmodule Turnstile.Fga do
  @moduledoc """
  The OpenFGA adapter. Facts become tuples in a store of the engine's own,
  rules become a model that is immutable and named by id, and a drain keeps
  that store in step with the application's tables, which is what makes this
  adapter's working state a copy rather than the tables themselves.

  An operation is a relation of the model, `can_` and the operation's name,
  and a decision is one `Check` under the model the configuration pins. A
  batch is `BatchCheck`, a scope is `ListObjects` turned into a `dynamic`
  over identifiers, and an explanation is `Expand`, whose tree is the path.

  What this package holds, and what each piece is for:

  - `Turnstile.Fga.Client`, the only path to the server. Eight calls, each
    answering a value or an engine error, none of them raising.
    `Turnstile.Fga.Client.Fake` is the same behaviour on an `Agent`.
  - `Turnstile.Fga.TupleMapping`, what an application states about its
    tables: which object types it writes, which objects of a type there are,
    which objects one change can have affected, and which tuples an object
    requires. Every answer is read from the rows as they stand, which is
    what lets a drain write differences.
  - `Turnstile.Fga.Outbox`, the markers a drain works from. A handler on the
    change event writes one marker per affected object in the transaction
    that changed the rows, and a `Turnstile.Relay` runner delivers them: per
    object, the difference between what the rows require and what the store
    holds.
  - `Turnstile.Fga.Binding`, what the configuration entry does not carry:
    the mediated repo the markers and the tables are read through, the model
    file the store is published from, the mapping, and the guard.
  - `Turnstile.Fga.Guard`, a precondition on the environment a binding may
    name, which every callback consults before it asks, for a fact about the
    call that no tuple should carry.
  - `Turnstile.Fga.Version`, the model published as a policy version.
  - `Turnstile.Fga.Migration`, the outbox table, which a thin application's
    migration creates.
  - `Turnstile.Fga.OutboxCase`, `Turnstile.Fga.TupleMappingCase`, and
    `Turnstile.Fga.GuardCase`, which hold an application's mapping, drain,
    and guard to what a decision relies on. The first two write and take
    away a `Turnstile.Fga.Population` of the application's own rows.

  Two declarations of this adapter in any domain: its scope is capped at
  what one `ListObjects` answers with, and settling it is draining its
  outbox until nothing is left.
  """

  @behaviour Turnstile.Adapter

  use Boundary,
    deps: [Turnstile, Turnstile.Relay, Ecto, NimbleOptions],
    exports: [
      Binding,
      Client,
      Client.BatchCheck,
      Client.Check,
      Client.Expand,
      Client.Http,
      Client.ListObjects,
      Client.Page,
      Client.Read,
      Client.Tree,
      Client.Write,
      Condition,
      Consistency,
      Drift,
      Guard,
      GuardCase,
      Model,
      Outbox,
      OutboxCase,
      Population,
      TupleKey,
      TupleMapping,
      TupleMappingCase,
      Version
    ]

  alias Turnstile.Error
  alias Turnstile.Fga.Adapter.Decide
  alias Turnstile.Fga.Adapter.Settle
  alias Turnstile.Fga.Adapter.Store
  alias Turnstile.Fga.Adapter.Version
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Drift
  alias Turnstile.Fga.Outbox
  alias Turnstile.PolicyVersion
  alias Turnstile.Relay.Cursor

  @schema NimbleOptions.new!(
            endpoint: [
              type: :any,
              required: true,
              doc: "Where the server is: the address of one, or the process a fake runs on."
            ],
            store_id: [type: :string, required: true, doc: "The store a drain writes and decisions read."],
            model_id: [
              type: :string,
              doc:
                "The model every question is pinned to. Absent until the first publish, " <>
                  "and a decision under an entry that pins none fails closed."
            ],
            client: [
              type: :atom,
              doc: "The `Turnstile.Fga.Client` implementation; the client over HTTP when absent."
            ]
          )

  @doc "Write the bound model to the server and emit the version it was published under; see `Turnstile.Fga.Version`."
  @spec publish() :: {:ok, PolicyVersion.t()} | {:error, Error.t()}
  def publish, do: Version.publish(__MODULE__)

  @doc """
  Mark every object of every type the mapping names, so the next drain
  brings the store to what the tables require for all of them. This is what
  fills a store whose rows were written before the handler was attached, and
  what a test calls when it has written rows the handler could not see.
  """
  @spec mark_all() :: :ok | {:error, Error.t()}
  def mark_all do
    with {:ok, %Store{} = store} <- Store.resolve(__MODULE__) do
      Outbox.mark(store.repo, Store.objects(store))
    end
  end

  @doc """
  The tuples the tables require against the tuples the store holds, as of
  the marker the drain has reached. A drift that is clean says the two
  agree; a drift that is not names every tuple that differs.
  """
  @spec reconcile() :: {:ok, Drift.t()} | {:error, Error.t()}
  def reconcile do
    with {:ok, %Store{} = store} <- Store.resolve(__MODULE__) do
      Store.drift(store, Cursor.position(store.repo, Outbox.runner()))
    end
  end

  @doc """
  A store of this name, carrying the bound model and every tuple the tables
  require, and its reference. The store the configuration names keeps
  serving while this one is filled, so a rebuild is a store to point the
  configuration at rather than an outage.

  A rebuild writes every object directly rather than through the outbox: a
  second store draining the same cursor would read markers the first drain
  had already deleted.
  """
  @spec rebuild(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def rebuild(name \\ "turnstile") when is_binary(name) do
    with {:ok, %Binding{} = binding} <- Binding.resolve(),
         {:ok, model} <- Binding.compiled(binding),
         {:ok, %Store{} = store} <- Store.resolve(__MODULE__),
         {:ok, %Store{} = fresh} <- Store.created(store, name, model),
         :ok <- Store.converge(fresh, Store.objects(fresh)) do
      {:ok, fresh.store}
    end
  end

  @impl Turnstile.Adapter
  def options_schema, do: @schema

  @impl Turnstile.Adapter
  def scope_cap, do: Decide.scope_cap()

  @impl Turnstile.Adapter
  def settle, do: Settle.now()

  @impl Turnstile.Adapter
  def authorize({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, options)
      when is_atom(operation) do
    case entry(options, :authorize, operation, environment) do
      {:ok, entry} -> Decide.one(entry, subject, operation, object)
      {:refused, entry} -> {:ok, Decide.refused(entry)}
      {:error, error} -> {:error, error}
    end
  end

  @impl Turnstile.Adapter
  def check({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, options)
      when is_atom(operation) do
    case entry(options, :check, operation, environment) do
      {:ok, entry} -> Decide.one(entry, subject, operation, object)
      {:refused, entry} -> {:ok, Decide.refused(entry)}
      {:error, error} -> {:error, error}
    end
  end

  @impl Turnstile.Adapter
  def batch({_kind, _account} = subject, operation, objects, %{now: _now} = environment, options)
      when is_atom(operation) and is_list(objects) do
    case entry(options, :batch, operation, environment) do
      {:ok, entry} -> Decide.many(entry, subject, operation, objects)
      {:refused, entry} -> {:ok, Decide.refused_all(entry, objects)}
      {:error, error} -> {:error, error}
    end
  end

  @impl Turnstile.Adapter
  def scope({_kind, _account} = subject, operation, object_type, %{now: _now} = environment, options)
      when is_atom(operation) and is_atom(object_type) do
    case entry(options, :scope, operation, environment) do
      {:ok, entry} -> Decide.scoped(entry, subject, operation, object_type)
      {:refused, entry} -> {:ok, Decide.refused_scope(entry)}
      {:error, error} -> {:error, error}
    end
  end

  @impl Turnstile.Adapter
  def explain({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, options)
      when is_atom(operation) do
    case entry(options, :explain, operation, environment) do
      {:ok, entry} -> Decide.explained(entry, subject, operation, object)
      {:refused, entry} -> {:ok, Decide.refused_explanation(entry)}
      {:error, error} -> {:error, error}
    end
  end

  # The guard a binding may name is asked before any question goes to the
  # server, so the binding is resolved first and a refusal is answered with
  # the entry the denial is reported under. Nothing else is read here: a
  # decision is one call to the store and no query of its own.
  defp entry(options, callback, operation, environment) do
    with {:ok, %Binding{} = binding} <- bound(callback),
         {:ok, entry} <- Decide.entry(options, callback, environment) do
      admits(binding, operation, environment, entry)
    end
  end

  defp admits(%Binding{guard: nil}, _operation, _environment, entry), do: {:ok, entry}

  defp admits(%Binding{guard: guard}, operation, %{now: _now} = environment, entry) do
    if guard.admits?(operation, environment), do: {:ok, entry}, else: {:refused, entry}
  end

  defp bound(callback) do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} -> {:ok, binding}
      {:error, %Error{reason: :invalid, detail: detail}} -> {:error, engine(callback, detail)}
    end
  end

  defp engine(callback, detail) do
    %Error{reason: :engine_unreachable, detail: "#{inspect(__MODULE__)} failed during #{callback}: #{detail}"}
  end
end
