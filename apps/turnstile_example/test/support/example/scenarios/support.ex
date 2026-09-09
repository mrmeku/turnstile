defmodule Example.Scenarios.Support do
  @moduledoc "What the scenario bodies share: the world, subjects, port shorthands, and the fresh and stale facts."

  use Boundary, top_level?: true, deps: [Example, Example.Fixture, Turnstile, Turnstile.Test, ExUnit]

  import ExUnit.Assertions

  alias Example.Documents
  alias Example.Fixture
  alias Example.Sessions
  alias Turnstile.Error
  alias Turnstile.Object
  alias Turnstile.Subject

  @doc "The world and the subject of an account."
  @spec subject(String.t()) :: Subject.t()
  defdelegate subject(id), to: Fixture

  @doc "Whether the port allows `read` on the document."
  @spec reads?(Subject.t(), Example.Document.t()) :: boolean()
  def reads?(%Subject{} = subject, %Example.Document{id: id}), do: Turnstile.check(subject, :read, Documents.object(id))

  @doc "Assert the context read the document."
  @spec assert_read(Subject.t(), Example.Document.t(), keyword()) :: Example.Document.t()
  def assert_read(%Subject{} = subject, %Example.Document{id: id}, opts \\ []) do
    assert {:ok, %Example.Document{id: ^id} = read} = Documents.read(subject, id, opts)
    read
  end

  @doc "Assert the context refused the read with the port's error."
  @spec assert_denied(Subject.t(), Example.Document.t(), keyword()) :: Error.NotAuthorized.t()
  def assert_denied(%Subject{} = subject, %Example.Document{id: id}, opts \\ []) do
    assert {:error, %Error.NotAuthorized{} = error} = Documents.read(subject, id, opts)
    refute reads?(subject, %Example.Document{id: id})
    error
  end

  @doc "The port options of a session that re-authenticated now."
  @spec fresh() :: keyword()
  def fresh, do: [facts: %{reauthenticated_at: DateTime.utc_now()}]

  @doc "The port options of a session that re-authenticated before the window."
  @spec stale() :: keyword()
  def stale, do: [facts: %{reauthenticated_at: DateTime.shift(DateTime.utc_now(), second: -(Sessions.window() + 60))}]

  @doc "The object reference of a portion."
  @spec portion(Example.Portion.t()) :: Object.t()
  def portion(%Example.Portion{id: id}), do: Documents.object(:portion, id)

  @doc "The revocation-latency report, written to the log and never asserted: total, commit, poll, and the floor."
  @spec latency_report(keyword()) :: :ok
  def latency_report(parts) when is_list(parts) do
    report("""
    revocation latency, #{adapter_name()}: total #{parts[:total]} ms
      commit #{parts[:commit]} ms
      projector_drain not needed
      poll #{parts[:poll]} ms, floor #{Turnstile.Test.poll_interval()} ms
      replica_lag not measured
      cache not measured
    """)
  end

  @doc "The policy-propagation report, written to the log and never asserted."
  @spec propagation_report(String.t(), keyword()) :: :ok
  def propagation_report(version, parts) when is_binary(version) and is_list(parts) do
    report("""
    policy_propagation, #{adapter_name()}: version #{version} total #{parts[:total]} ms
      publish #{parts[:publish]} ms
      poll #{parts[:poll]} ms, floor #{Turnstile.Test.poll_interval()} ms
      replica_lag not measured
      cache not measured
    """)
  end

  @doc "The adapter module the boot config names."
  @spec adapter_name() :: String.t()
  def adapter_name do
    {:ok, config} = Turnstile.Config.resolve()
    {adapter, _options} = Turnstile.Config.adapter(config)
    inspect(adapter)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
  defp report(text), do: IO.puts("\n" <> text)
end
