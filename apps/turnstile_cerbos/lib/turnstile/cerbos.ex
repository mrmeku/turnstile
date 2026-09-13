defmodule Turnstile.Cerbos do
  @moduledoc """
  The Cerbos adapter: rules are policy files, and a sidecar on the same host
  answers from them. The configuration entry carries the address of that
  sidecar and nothing else, since the address is where the process runs;
  what the adapter may read comes from the binding
  `Turnstile.Cerbos.Binding.bind/1` makes at boot beside the configuration,
  which names the mediated repo, the module that declares the attributes,
  the policy directory, and the commit of the policy repository that
  directory is at.

  Every call reads the declared attribute values through the bound repo and
  then asks the sidecar once. `check`, `authorize`, `batch`, and `explain`
  ask for a decision over the rows named and answer with the policy the
  sidecar matched. `scope` asks for a query plan and compiles the filter it
  answers into a `dynamic` over the object type
  (`Turnstile.Cerbos.Plan`); a plan this adapter does not express fails,
  and the caller asks the port for each row instead, which is the answer
  the declaration of a rule enforced this way records as limited.

  The commit is the version identifier of every decision, and
  `publish/0` appends it to the ledger the way a deploy is a version
  (`Turnstile.Cerbos.Version`). What reaches the sidecar is what the
  declarations name, so a policy cannot come to depend on a value no one
  declared: the moment the request carries, and each request-time fact an
  `environment` block declared, go as one principal attribute beside the
  subject's own (`Turnstile.Cerbos.Values.environment/2`).
  """

  @behaviour Turnstile.Adapter

  use Boundary,
    deps: [Turnstile, Turnstile.Test, Ecto, NimbleOptions],
    check: [apps: [:ecto_sql, :postgrex]],
    exports: [
      Attribute,
      Attributes,
      Binding,
      Client,
      Coverage,
      Decide,
      Decisions,
      Decisions.Line,
      Finding,
      Plan,
      Propagation,
      Replay,
      Request,
      Values,
      Version
    ]

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Decide
  alias Turnstile.Cerbos.Version
  alias Turnstile.Error
  alias Turnstile.FactEvent

  @schema NimbleOptions.new!(
            address: [
              type: :string,
              required: true,
              doc: "The host and port the sidecar answers on, such as `127.0.0.1:3592`."
            ]
          )

  @doc "Append the bound policy directory's commit to the ledger; see `Turnstile.Cerbos.Version`."
  @spec publish() :: {:ok, :telemetry | :current | FactEvent.t()} | {:error, Error.t()}
  def publish, do: Version.publish(__MODULE__)

  @impl Turnstile.Adapter
  def options_schema, do: @schema

  @impl Turnstile.Adapter
  def requires_ledger, do: false

  @impl Turnstile.Adapter
  def scope_cap, do: :none

  @impl Turnstile.Adapter
  def authorize({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, options)
      when is_atom(operation) do
    explain(subject, operation, object, environment, options)
  end

  @impl Turnstile.Adapter
  def check({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, options)
      when is_atom(operation) do
    authorize(subject, operation, object, environment, options)
  end

  @impl Turnstile.Adapter
  def batch({_kind, _account} = subject, operation, objects, %{now: _now} = environment, options)
      when is_atom(operation) and is_list(objects) do
    with {:ok, binding, address} <- bound(:batch, options) do
      named(Decide.many(binding, address, subject, operation, objects, environment), :batch)
    end
  end

  @impl Turnstile.Adapter
  def scope({_kind, _account} = subject, operation, object_type, %{now: _now} = environment, options)
      when is_atom(operation) and is_atom(object_type) do
    with {:ok, binding, address} <- bound(:scope, options) do
      named(Decide.scoped(binding, address, subject, operation, object_type, environment), :scope)
    end
  end

  @impl Turnstile.Adapter
  def explain({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, options)
      when is_atom(operation) do
    with {:ok, binding, address} <- bound(:explain, options) do
      named(Decide.one(binding, address, subject, operation, object, environment), :explain)
    end
  end

  # A failure's detail becomes the engine error, naming the callback that failed.
  defp named({:error, detail}, callback) when is_binary(detail) do
    {:error, engine(callback, detail)}
  end

  defp named(other, _callback), do: other

  defp bound(operation, options) do
    with {:ok, address} <- address(operation, options),
         {:ok, %Binding{} = binding} <- resolved(operation) do
      {:ok, binding, address}
    end
  end

  defp resolved(operation) do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} -> {:ok, binding}
      {:error, %Error{reason: :invalid, detail: detail}} -> {:error, engine(operation, detail)}
    end
  end

  defp address(operation, options) do
    case Keyword.fetch(options, :address) do
      {:ok, address} when is_binary(address) -> {:ok, address}
      _absent -> {:error, engine(operation, "the configuration entry names no address for the sidecar")}
    end
  end

  defp engine(operation, detail) do
    %Error{reason: :engine_unreachable, detail: "#{inspect(__MODULE__)} failed during #{operation}: #{detail}"}
  end
end
