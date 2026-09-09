defmodule Turnstile.Postgres.Session do
  @moduledoc """
  Where the settings meet the connection. `set_config(name, value, true)`
  is local to a transaction, so a call that is not already inside one opens
  a transaction for the length of the call and the settings leave with it.
  A call already inside a transaction sets them there, and the next call in
  that transaction sets its own over them, so two subjects in one
  transaction never read each other's.

  Every call puts back what it set: each name it wrote goes to the empty
  string as the function returns, whether the function returned or raised.
  A transaction the adapter did not open outlives the call, and so does one
  the adapter opens inside another, which the database keeps as a savepoint
  whose settings survive its release. Without the clearing, a statement the
  seam admits outside a decision, later in the same transaction, would run
  under the settings of the decision before it, and a policy written for
  "no operation in force" would not hold. The clearing statement runs
  through the repo's non-raising channel, so a transaction the function
  already aborted keeps the error the function raised.

  Each statement runs through the bound repo's raw channel under the
  library exemption, and each is one query in the shape counts.
  """

  alias Turnstile.Postgres.Settings
  alias Turnstile.Subject

  @exemption {:exempt, :library}
  @stash {__MODULE__, :settings}

  @doc "Run the function with the settings in force on the connection it uses."
  @spec around(module(), Settings.t(), (-> result)) :: result when result: term()
  def around(repo, %Settings{} = settings, fun) when is_atom(repo) and is_function(fun, 0) do
    if repo.in_transaction?() do
      set(repo, settings, fun)
    else
      {:ok, value} = repo.transaction(fn -> set(repo, settings, fun) end)
      value
    end
  end

  @doc """
  Keep the settings a call ran under, so a query the seam mediates with
  that call's decision can run under the same ones. One slot per process,
  keyed by the subject and the operation, because a decision names those
  two and the next call overwrites the last.
  """
  @spec remember(Subject.t(), atom(), Settings.t()) :: :ok
  def remember(%Subject{} = subject, operation, %Settings{} = settings) when is_atom(operation) do
    Process.put(@stash, {key(subject, operation), settings})
    :ok
  end

  @doc "The kept settings for a subject and an operation, or `nil` when the slot holds another call's."
  @spec recall(Subject.t(), atom()) :: Settings.t() | nil
  def recall(%Subject{} = subject, operation) when is_atom(operation) do
    wanted = key(subject, operation)

    case Process.get(@stash) do
      {^wanted, %Settings{} = settings} -> settings
      _miss -> nil
    end
  end

  defp key(%Subject{id: id}, operation), do: {id, operation}

  defp set(repo, settings, fun) do
    {statement, params} = Settings.statement(settings)
    _result = repo.query!(statement, params, turnstile: @exemption)

    try do
      fun.()
    after
      clear(repo, settings)
    end
  end

  defp clear(repo, settings) do
    {statement, params} = Settings.statement(Settings.cleared(settings))
    _result = repo.query(statement, params, turnstile: @exemption)
    :ok
  end
end
