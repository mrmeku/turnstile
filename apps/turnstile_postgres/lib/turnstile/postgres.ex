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

  *Answers.* `decide` runs one statement under those settings: a row the
  `SELECT` policy of the operation does not admit is a denial, and where
  the operation has an `UPDATE` gate its `USING` expression is read in the
  same statement, so an answer given before a write agrees with what
  `WITH CHECK` will do to the write.
  `scope` runs no statement and answers the rule `true`, because the policy
  narrows the query when the repo runs it; the reason names the policy and
  the SHA-256 of the settings the database will read, which together are
  what it enforced.

  *Policy versions.* The version is the migration number.
  `Turnstile.Postgres.Migration.publish!/2` reads the policies back from
  `pg_policy` and appends the version in the same transaction as the DDL.

  The database does not report which policy admitted a row, so an answer
  names the policy of the operation and nothing further. The replica-lag
  component of revocation latency is reported "not measured", because
  every statement goes to the primary.
  """

  @behaviour Turnstile.Adapter

  use Boundary,
    deps: [Turnstile, Ecto, NimbleOptions],
    check: [apps: [:ecto_sql, :postgrex]],
    exports: [Binding, Catalog, Coverage, Migration, Policy, Version]

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Postgres.Adapter.Decide
  alias Turnstile.Postgres.Adapter.Session
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Core.Settings

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
  def scope_cap, do: :none

  @impl Turnstile.Adapter
  def decide({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, _options)
      when is_atom(operation) do
    with {:ok, binding, catalog} <- ready(:decide) do
      Decide.one(binding, catalog, subject, operation, object, environment)
    end
  end

  @impl Turnstile.Adapter
  def scope({_kind, _account} = subject, operation, object_type, %{now: _now} = environment, _options)
      when is_atom(operation) and is_atom(object_type) do
    with {:ok, binding, catalog} <- ready(:scope) do
      settings = Settings.of(subject, operation, environment)
      :ok = Session.remember(subject, operation, settings)
      {:ok, scoped(Decide.scope(binding, catalog, operation, object_type, settings))}
    end
  end

  @impl Turnstile.Adapter
  def around_query(_query_or_changeset, %Decision{} = decision, fun) when is_function(fun, 0) do
    case Binding.resolve() do
      {:ok, %Binding{repo: repo}} -> Session.around(repo, settings_of(decision), fun)
      {:error, _unbound} -> fun.()
    end
  end

  defp scoped(%Answer{verdict: :allow} = answer), do: {dynamic([_row], true), answer}
  defp scoped(%Answer{verdict: :deny} = answer), do: {dynamic([_row], false), answer}

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

  defp bound(operation) do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} -> {:ok, binding}
      {:error, %Error{reason: :invalid, detail: detail}} -> {:error, engine(operation, detail)}
    end
  end

  defp engine(operation, detail),
    do: %Error{reason: :engine_unreachable, detail: "#{inspect(__MODULE__)} failed during #{operation}: #{detail}"}
end
