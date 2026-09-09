defmodule Turnstile.Fga do
  @moduledoc """
  The OpenFGA adapter. Facts become tuples in a store of the engine's own,
  rules become a model that is immutable and named by id, and the projector
  drains the ledger into that store, which is why this adapter requires a
  ledger: its working state is a copy rather than the application's tables.

  An operation is a relation of the model, `can_` and the operation's name,
  and a decision is one `Check` under the model the configuration pins. A
  batch is `BatchCheck`, a scope is `ListObjects` turned into a `dynamic`
  over identifiers, and an explanation is `Expand`, whose tree is the path.
  `Turnstile.Fga.Decide` holds those translations and the constants they use.

  What this package holds, and what each piece is for:

  - `Turnstile.Fga.Client`, the only path to the server. Eight calls, each
    answering a value or an engine error, none of them raising.
    `Turnstile.Fga.Client.Fake` is the same behaviour on an `Agent`, which
    is where the projector's own cases run.
  - `Turnstile.Fga.TupleMapping`, what an application states about its
    facts: which objects an event can have changed, and which tuples an
    object requires. Both are read from the fold rather than from one event,
    which is what lets the projector write differences.
  - `Turnstile.Fga.Projector`, `Turnstile.Projection` over that mapping:
    a drain by difference, a checkpoint in the application's own database, a
    rebuild into a store of its own, and a reconcile against what the store
    reports.
  - `Turnstile.Fga.Binding`, what the configuration entry does not carry:
    the repo the checkpoint is read through, the model file the store is
    published from, and the mapping.
  - `Turnstile.Fga.Version`, the model published as a policy version, and
    `Turnstile.Fga.Replay`, a past state in a server that is thrown away.
  - `Turnstile.Fga.Migration`, the checkpoint table, which a thin
    application's migration creates.

  Two declarations of this adapter in any domain: it requires a ledger,
  since nothing drains without one, and its scope is capped at what one
  `ListObjects` answers with.
  """

  @behaviour Turnstile.Adapter

  use Boundary,
    deps: [Turnstile, Turnstile.Ledger.Reader, Ecto, NimbleOptions],
    exports: [
      Binding,
      Checkpoint,
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
      Decide,
      Model,
      Projector,
      Replay,
      TupleKey,
      TupleMapping,
      Version
    ]

  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Checkpoint
  alias Turnstile.Fga.Decide
  alias Turnstile.Fga.Version
  alias Turnstile.Object
  alias Turnstile.Subject

  @schema NimbleOptions.new!(
            endpoint: [
              type: :any,
              required: true,
              doc: "Where the server is: the address of one, or the process a fake runs on."
            ],
            store_id: [type: :string, required: true, doc: "The store the projector drains into and decisions read."],
            model_id: [
              type: :string,
              doc:
                "The model every question is pinned to. Absent until the first publish, " <>
                  "and a decision under an entry that pins none fails closed."
            ],
            drain_interval: [
              type: :pos_integer,
              default: 1_000,
              doc: "Milliseconds between drains, for the projector process a thin application starts."
            ],
            client: [
              type: :atom,
              doc: "The `Turnstile.Fga.Client` implementation; the client over HTTP when absent."
            ]
          )

  @doc "Publish the bound model when the ledger's latest names another; see `Turnstile.Fga.Version`."
  @spec publish() :: {:ok, :current | FactEvent.t()} | {:error, Error.Invalid.t() | Error.Engine.t()}
  def publish, do: Version.publish(__MODULE__)

  @impl Turnstile.Adapter
  def options_schema, do: @schema

  @impl Turnstile.Adapter
  def requires_ledger, do: true

  @impl Turnstile.Adapter
  def scope_cap, do: Decide.scope_cap()

  @impl Turnstile.Adapter
  def authorize(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, options)
      when is_atom(operation) do
    with {:ok, entry} <- entry(options, :authorize, environment) do
      Decide.one(entry, subject, operation, object)
    end
  end

  @impl Turnstile.Adapter
  def check(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, options)
      when is_atom(operation) do
    with {:ok, entry} <- entry(options, :check, environment) do
      Decide.one(entry, subject, operation, object)
    end
  end

  @impl Turnstile.Adapter
  def batch(%Subject{} = subject, operation, objects, %Environment{} = environment, options)
      when is_atom(operation) and is_list(objects) do
    with {:ok, entry} <- entry(options, :batch, environment) do
      Decide.many(entry, subject, operation, objects)
    end
  end

  @impl Turnstile.Adapter
  def scope(%Subject{} = subject, operation, object_type, %Environment{} = environment, options)
      when is_atom(operation) and is_atom(object_type) do
    with {:ok, entry} <- entry(options, :scope, environment) do
      Decide.scoped(entry, subject, operation, object_type)
    end
  end

  @impl Turnstile.Adapter
  def explain(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, options)
      when is_atom(operation) do
    with {:ok, entry} <- entry(options, :explain, environment) do
      Decide.explained(entry, subject, operation, object)
    end
  end

  # The position the store has been drained to is read where the
  # application's own tables are, so the binding is resolved for the repo
  # that holds the checkpoint before any question is asked.
  defp entry(options, callback, environment) do
    with {:ok, %Binding{} = binding} <- bound(callback),
         {:ok, entry} <- Decide.entry(options, callback, environment) do
      {:ok, Decide.applied(entry, Checkpoint.position(binding.repo, entry.store))}
    end
  end

  defp bound(callback) do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} -> {:ok, binding}
      {:error, %Error.Invalid{detail: detail}} -> {:error, engine(callback, detail)}
    end
  end

  defp engine(callback, detail), do: %Error.Engine{adapter: __MODULE__, operation: callback, detail: detail}
end
