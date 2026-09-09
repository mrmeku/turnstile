defmodule ExampleRbac.Rules do
  @moduledoc """
  The policy operations the scenarios need from this binding: a tightened
  policy, under which a program member no longer reads, bound and published
  for the calling process; the boot policy restored; the boot policy
  published again, which is what the boot itself does; and a question asked
  again under a version and a state a replay names.

  Rules here are Elixir modules, so the version a replay names is got back
  by running the release that carries it: this binding checks that the
  running one is that release and refuses the replay otherwise, because a
  release that has moved on would answer under rules the decision was never
  made under. The state is got back inside a transaction that rolls back,
  which puts the relationships of the fold in the tables for the length of
  the question and leaves them as the question found them.
  """

  @behaviour Example.Scenarios.Rules

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Fixture,
      Example.Scenarios,
      ExampleRbac,
      ExampleRbac.Tightened,
      Turnstile,
      Turnstile.Code,
      Turnstile.Ledger.Replay
    ]

  alias Example.Fixture
  alias Example.Repo
  alias Example.Scenarios.Rules
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Version
  alias Turnstile.Error
  alias Turnstile.Ledger.Replay

  @impl Rules
  def publish_tightened do
    :ok = Binding.override(policy: ExampleRbac.Tightened)
    {:ok, config} = Turnstile.Config.resolve()

    with {:ok, _published} <- Turnstile.Code.publish() do
      {:ok, Version.of(Turnstile.Code, ExampleRbac.Tightened, config, config.clock.now())}
    end
  end

  @impl Rules
  def restore, do: Binding.override(policy: ExampleRbac.Policy)

  @impl Rules
  def publish_boot do
    {:ok, _published} = Turnstile.Code.publish()
    :ok
  end

  @impl Rules
  def replay(%Replay{} = replay, fun) when is_function(fun, 0) do
    :ok = same_release!(replay)

    {:error, {:replayed, answer}} =
      Repo.transaction(fn ->
        :ok = Fixture.restore!(replay.fold)
        Repo.rollback({:replayed, fun.()})
      end)

    answer
  end

  # The running release against the one the replay names. There is nothing
  # to be done about a mismatch here: the predicates of that version are in
  # a commit, and getting them back means checking it out and running its
  # port.
  defp same_release!(%Replay{policy_version: version}) do
    {:ok, binding} = Binding.resolve()
    running = Version.ref(binding.policy)

    if running == version.version do
      :ok
    else
      raise %Error.Unsupported{
        adapter: Turnstile.Code,
        feature: :replay,
        note: "the running release is at #{running} and the replay names #{version.version}: check out that commit"
      }
    end
  end
end
