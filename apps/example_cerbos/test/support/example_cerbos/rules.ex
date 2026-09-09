defmodule ExampleCerbos.Rules do
  @moduledoc """
  The policy operations the scenarios need from this binding. The rules are
  policy files a sidecar reads, so a rule change is a file written into the
  directory the sidecar watches and a commit the binding names from then on.
  Publishing writes the file, overrides the commit, and appends the version;
  restoring puts the file back and waits for the sidecar to be serving the
  boot rules again, since the scenario asks its next question with no poll.

  A replay is the same fact from the other side: the version's policy files
  are its content, so getting them back means writing them into a directory
  of their own and raising a sidecar on it, which the run's own sidecar
  cannot be, because a sidecar reads one directory and the run's is
  answering other questions from its own. The state comes back inside a
  transaction that rolls back, which puts the relationships of the fold in
  the tables for the length of the question and leaves them as the question
  found them.
  """

  @behaviour Example.Scenarios.Rules

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Fixture,
      Example.Scenarios,
      ExampleCerbos.Tightened,
      Turnstile,
      Turnstile.Cerbos,
      Turnstile.Ledger.Replay,
      Turnstile.Test
    ]

  alias Example.Fixture
  alias Example.Repo
  alias Example.Scenarios.Rules
  alias ExampleCerbos.Tightened
  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Client
  alias Turnstile.Cerbos.Propagation
  alias Turnstile.Cerbos.Request
  alias Turnstile.Cerbos.Version
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.Ledger.Replay
  alias Turnstile.Test

  @swapped {__MODULE__, :swapped}

  @impl Rules
  def publish_tightened do
    {:ok, binding} = Binding.resolve()
    previous = Propagation.swap!(binding.policies, [{Tightened.path(), Tightened.document()}])
    _replaced = Process.put(@swapped, {binding.policies, previous})
    :ok = Binding.override(commit: Tightened.commit())

    with {:ok, _published} <- Turnstile.Cerbos.publish() do
      {:ok, tightened} = Binding.resolve()
      {:ok, config} = Config.resolve()
      Version.of(Turnstile.Cerbos, tightened, config, config.clock.now())
    end
  end

  @impl Rules
  def restore do
    case Process.get(@swapped) do
      {directory, previous} ->
        :ok = Propagation.restore!(directory, previous)
        _swapped = Process.delete(@swapped)
        :ok

      nil ->
        :ok
    end

    :ok = Binding.override(commit: Application.fetch_env!(:example_cerbos, :commit))
    in_force!()
  end

  @impl Rules
  def publish_boot do
    {:ok, _published} = Turnstile.Cerbos.publish()
    :ok
  end

  @impl Rules
  def replay(%Replay{} = replay, fun) when is_function(fun, 0) do
    dir = Path.join([File.cwd!(), "tmp", "replay-" <> suffix()])
    directory = Path.join(dir, "policies")
    :ok = Turnstile.Cerbos.Replay.build!(to: directory, policies: policies!(replay))
    sidecar = Test.Cerbos.start_supervised!(policies: directory, dir: dir)
    overrides = [policies: sidecar.policies, commit: replay.policy_version.version]

    Test.with_config([adapter: {Turnstile.Cerbos, address: sidecar.address}], fn ->
      bound(overrides, replay, fun)
    end)
  end

  # The question asked of the sidecar that reads the version's own policy
  # files, under the binding that names them.
  defp bound(overrides, replay, fun) do
    Binding.override(overrides, fn -> rolled_back(fn -> asked(replay, fun) end) end)
  end

  # The relationships of the fold in the tables, the question asked, and the
  # tables left as they were.
  defp asked(%Replay{} = replay, fun) do
    :ok = Fixture.restore!(replay.fold)
    fun.()
  end

  defp rolled_back(fun) do
    {:error, {:replayed, answer}} = Repo.transaction(fn -> Repo.rollback({:replayed, fun.()}) end)
    answer
  end

  # The policy files of the version by value. A version above the content cap
  # carries a pointer to the directory and the commit instead, and reading
  # those back is a checkout of that commit.
  defp policies!(%Replay{policy_version: version}) do
    case version do
      %{content: text} when is_binary(text) ->
        text

      %{version: commit, pointer: pointer} ->
        raise %Error.Unsupported{
          adapter: Turnstile.Cerbos,
          feature: :replay,
          note: "version #{commit} carries #{pointer} rather than its policies: start a sidecar on that directory"
        }
    end
  end

  # Nothing tells a sidecar that its directory changed and nothing answers
  # whether it has read it, so being in force is a question the boot rules
  # answer one way and the tightened rules the other: a program member reads
  # a document under nothing else. The question carries its own values, so it
  # touches no table and holds no connection.
  defp in_force! do
    {:ok, config} = Config.resolve()
    {Turnstile.Cerbos, options} = Config.adapter(config)
    body = Request.logged(principal(config), resource(), ["read"])
    true = Test.poll(fn -> allowed?(options[:address], body) end)
    :ok
  end

  defp allowed?(address, body) do
    case Client.check_resources(address, body) do
      {:ok, %{"results" => [result | _rest]}} -> result["actions"]["read"] == "EFFECT_ALLOW"
      _unanswered -> false
    end
  end

  defp principal(config) do
    now = DateTime.to_iso8601(DateTime.truncate(config.clock.now(), :second))

    %{
      id: "turnstile.restore",
      roles: ["user"],
      attr: %{
        employment: "federal",
        nationality: "US",
        environment: %{now: now, reauthenticated_at: nil}
      }
    }
  end

  defp resource do
    %{
      kind: "document",
      id: "0",
      attr: %{
        program_roles: ["member"],
        office_roles: [],
        effective_controls: [],
        releasable_to: [],
        agency_nationalities: ["US"],
        listed: [],
        decontrol: nil
      }
    }
  end

  defp suffix, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
end
