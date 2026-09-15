defmodule Example.Scenarios.Support do
  @moduledoc "What the scenario bodies share: the subject, port shorthands, the fresh and stale facts, and the latency report."

  use Boundary, top_level?: true, deps: [Example, Example.Fixture, Turnstile, Turnstile.Test, ExUnit]

  import ExUnit.Assertions

  alias Example.Application.Documents
  alias Example.Domain.Document
  alias Example.Domain.Sessions
  alias Example.Fixture
  alias Turnstile.Error

  @doc "The world and the subject of an account."
  @spec subject(String.t()) :: Turnstile.subject()
  defdelegate subject(id), to: Fixture

  @doc "Whether the port allows `read` on the document."
  @spec reads?(Turnstile.subject(), Document.t()) :: boolean()
  def reads?({_kind, _account} = subject, %Document{id: id}), do: Turnstile.check(subject, :read, Documents.object(id))

  @doc "Assert the context read the document."
  @spec assert_read(Turnstile.subject(), Document.t(), keyword()) :: Document.t()
  def assert_read({_kind, _account} = subject, %Document{id: id}, opts \\ []) do
    assert {:ok, %Document{id: ^id} = read} = Documents.read(subject, id, opts)
    read
  end

  @doc "Assert the context refused the read with the port's error."
  @spec assert_denied(Turnstile.subject(), Document.t(), keyword()) :: Error.t()
  def assert_denied({_kind, _account} = subject, %Document{id: id}, opts \\ []) do
    error = assert_refused(Documents.read(subject, id, opts), :read)
    refute reads?(subject, %Document{id: id})
    error
  end

  @doc "Assert the port refused the call the result came from, naming the operation it refused."
  @spec assert_refused(term(), atom()) :: Error.t()
  def assert_refused(result, operation) when is_atom(operation) do
    assert {:error, %Error{} = error} = result
    assert Exception.message(error) =~ "may not #{operation}"
    error
  end

  @doc "The port options of a session that re-authenticated now."
  @spec fresh() :: keyword()
  def fresh, do: [env: %{reauthenticated_at: DateTime.utc_now()}]

  @doc "The port options of a session that re-authenticated before the window."
  @spec stale() :: keyword()
  def stale, do: [env: %{reauthenticated_at: DateTime.shift(DateTime.utc_now(), second: -(Sessions.window() + 60))}]

  @doc """
  Wait until every fact the tests have written has reached the engine, where
  the bound adapter keeps state of its own. Answers `:none` where there is
  nothing to wait for, so a scenario body calls it whatever is bound.
  """
  @spec settle() :: :ok | :none
  defdelegate settle(), to: Turnstile.Test

  @doc """
  The revocation-latency report, written to the log and never asserted: total,
  commit, drain, poll, and the floor. The `drain` part is the milliseconds the
  engine's copy of the facts took to catch up, or `nil` where the bound
  adapter keeps no copy to drain.
  """
  @spec latency_report(keyword()) :: :ok
  def latency_report(parts) when is_list(parts) do
    report("""
    revocation latency, #{adapter_name()}: total #{parts[:total]} ms
      commit #{parts[:commit]} ms
      #{drained(parts[:drain])}
      poll #{parts[:poll]} ms, floor #{Turnstile.Test.poll_interval()} ms
      replica_lag not measured
      cache not measured
    """)
  end

  @doc "The adapter module as text, for a report."
  @spec adapter_name() :: String.t()
  def adapter_name do
    {:ok, config} = Turnstile.Config.resolve()
    {adapter, _options} = Turnstile.Config.adapter(config)
    inspect(adapter)
  end

  # An adapter that answers from the tables it is bound to keeps no state of
  # its own, and `Turnstile.Test.settle/0` answers `:none` there, so the line
  # says so rather than reporting a zero that reads like a measurement.
  defp drained(nil), do: "settle not needed"
  defp drained(milliseconds) when is_integer(milliseconds), do: "settle #{milliseconds} ms"

  # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
  defp report(text), do: IO.puts("\n" <> text)
end
