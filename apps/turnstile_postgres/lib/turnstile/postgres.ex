defmodule Turnstile.Postgres do
  @moduledoc """
  Row-level security as the adapter. The rules are Postgres policies on the
  tables themselves, written by migrations, and the database enforces them
  on every statement, including statements this library never sees. The
  adapter takes no options, so its configuration entry is the bare module,
  and it finds the repo and the schemas through the binding
  `Turnstile.Postgres.Binding.bind/1` makes at boot beside the
  configuration.

  Three mechanisms.

  *Session settings.* `around_query/3` runs `set_config(name, value, true)`
  for `turnstile.subject_id`, `turnstile.subject_kind`,
  `turnstile.operation`, `turnstile.now`, and one name per fact the caller
  supplied, inside a transaction it opens where none is open, so the
  settings leave with the call and two subjects in one transaction each set
  their own. Policies read them with `current_setting(name, true)`.

  *Answers.* `check`, `authorize`, and `batch` run one statement per object
  type under those settings: a row the `SELECT` policy of the operation
  does not admit is a denial, and where the operation has an `UPDATE` gate
  its `USING` expression is read in the same statement, so an answer given
  before a write agrees with what `WITH CHECK` will do to the write.
  `scope` runs no statement and answers the rule `true`, because the policy
  narrows the query when the repo runs it; the reason names the policy and
  the SHA-256 of the settings the database will read, which together are
  what it enforced.

  *Policy versions.* The version is the migration number.
  `Turnstile.Postgres.Migration.publish!/2` reads the policies back from
  `pg_policy` and appends the version in the same transaction as the DDL.

  `explain/5` answers the verdict and names nothing further: the database
  does not report which policy admitted a row. The replica-lag component of
  revocation latency is reported "not measured", because every statement
  goes to the primary.
  """

  @behaviour Turnstile.Adapter

  use Boundary,
    deps: [Turnstile, Ecto, NimbleOptions],
    check: [apps: [:ecto_sql, :postgrex]],
    exports: [Binding, Catalog, Coverage, Decide, Migration, Name, Policy, Replay, Session, Settings, Version]

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Explanation
  alias Turnstile.Object
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Decide
  alias Turnstile.Postgres.Session
  alias Turnstile.Postgres.Settings
  alias Turnstile.Scope
  alias Turnstile.Subject

  @doc """
  Read the policies and the version once, so no call on the request path
  pays for the read. An application calls this at boot, after the binding.
  """
  @spec load!() :: Catalog.t()
  def load! do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} -> Catalog.load!(binding)
      {:error, error} -> raise error
    end
  end

  @doc """
  Read the policies and the version again, for an application that ran a
  migration after boot. Every call after this one reads what the database
  now holds.
  """
  @spec reload!() :: Catalog.t()
  def reload! do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} -> Catalog.reload!(binding)
      {:error, error} -> raise error
    end
  end

  @doc "The component of revocation latency this adapter cannot measure."
  @spec replica_lag() :: String.t()
  def replica_lag, do: "not measured"

  @impl Turnstile.Adapter
  def requires_ledger, do: false

  @impl Turnstile.Adapter
  def scope_cap, do: :none

  @impl Turnstile.Adapter
  def authorize(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, _options)
      when is_atom(operation) do
    with {:ok, binding, catalog} <- ready(:authorize) do
      named(Decide.one(binding, catalog, subject, operation, object, environment), :authorize)
    end
  end

  @impl Turnstile.Adapter
  def check(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, options)
      when is_atom(operation) do
    authorize(subject, operation, object, environment, options)
  end

  @impl Turnstile.Adapter
  def batch(%Subject{} = subject, operation, objects, %Environment{} = environment, _options)
      when is_atom(operation) and is_list(objects) do
    with {:ok, binding, catalog} <- ready(:batch) do
      named(Decide.many(binding, catalog, subject, operation, objects, environment), :batch)
    end
  end

  @impl Turnstile.Adapter
  def scope(%Subject{} = subject, operation, object_type, %Environment{} = environment, _options)
      when is_atom(operation) and is_atom(object_type) do
    with {:ok, binding, catalog} <- ready(:scope) do
      settings = Settings.of(subject, operation, environment)
      :ok = Session.remember(subject, operation, settings)
      {:ok, scoped(Decide.scope(binding, catalog, operation, object_type, settings))}
    end
  end

  @impl Turnstile.Adapter
  def explain(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, options)
      when is_atom(operation) do
    with {:ok, %Answer{} = answer} <- authorize(subject, operation, object, environment, options) do
      {:ok, %Explanation{answer: answer, matched: []}}
    end
  end

  @impl Turnstile.Adapter
  def around_query(_query_or_changeset, %Decision{} = decision, fun) when is_function(fun, 0) do
    case Binding.resolve() do
      {:ok, %Binding{repo: repo}} -> Session.around(repo, settings_of(decision), fun)
      {:error, _unbound} -> fun.()
    end
  end

  defp scoped(%Answer{verdict: :allow} = answer), do: %Scope{rule: dynamic([_row], true), answer: answer}
  defp scoped(%Answer{verdict: :deny} = answer), do: %Scope{rule: dynamic([_row], false), answer: answer}

  # The settings the call that produced the decision ran under, or, where
  # that call is out of reach, the ones the decision alone determines: no
  # supplied fact, so a policy that reads one denies.
  defp settings_of(%Decision{subject: subject, operation: operation, at: at}) do
    Session.recall(subject, operation) || Settings.of(subject, operation, at)
  end

  defp ready(operation) do
    with {:ok, %Binding{} = binding} <- bound(operation) do
      loaded(binding, operation)
    end
  end

  defp loaded(binding, operation) do
    {:ok, binding, Catalog.current!(binding)}
  rescue
    error -> {:error, engine(operation, Exception.message(error))}
  end

  # A failure's detail becomes the engine error, naming the callback that failed.
  defp named({:error, detail}, callback) when is_binary(detail), do: {:error, engine(callback, detail)}
  defp named(other, _callback), do: other

  defp bound(operation) do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} -> {:ok, binding}
      {:error, %Error.Invalid{detail: detail}} -> {:error, engine(operation, detail)}
    end
  end

  defp engine(operation, detail), do: %Error.Engine{adapter: __MODULE__, operation: operation, detail: detail}
end
