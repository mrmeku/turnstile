defmodule Turnstile.Code.VersionTest do
  use ExUnit.Case, async: true

  alias Turnstile.Code.Binding
  alias Turnstile.Code.Conformance.Predicates
  alias Turnstile.Code.Conformance.Roles
  alias Turnstile.Code.Policy
  alias Turnstile.Code.Version
  alias Turnstile.Config
  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Memory
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject
  alias Turnstile.TestRepos.Sandboxed

  setup do
    agent = start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})
    :ok = Turnstile.Test.with_config(adapter: Turnstile.Code, ledger: {Memory, agent: agent})
    :ok = Binding.override(policy: Roles, repo: Sandboxed)
    {:ok, ledger: {Memory, agent: agent}}
  end

  test "the version carries the commit, the hash of the rule modules, and the role table as data" do
    {:ok, config} = Config.resolve()
    at = DateTime.utc_now()
    version = Version.of(Turnstile.Code, Roles, config, at)

    assert %PolicyVersion{adapter: Turnstile.Code, version: "conformance", author: "turnstile_rbac"} = version
    assert version.approval == "the conformance suite"
    assert version.at == at
    assert version.content_hash == Version.content_hash(Roles)
    assert String.length(version.content_hash) == 64
    assert version.content =~ "modules: #{inspect(Predicates)}, #{inspect(Roles)}"
    assert version.content =~ "  reader: read\n  editor: read, edit\n"
    assert version.pointer == nil
  end

  test "over the content cap the version carries a pointer to the modules" do
    :ok = Turnstile.Test.with_config(caps: [policy_content_bytes: 8])
    {:ok, config} = Config.resolve()
    version = Version.of(Turnstile.Code, Roles, config, DateTime.utc_now())
    assert version.content == nil
    assert version.pointer == "modules #{inspect(Predicates)}, #{inspect(Roles)}"
  end

  test "publish appends one event per version, never per boot", %{ledger: {Memory, options}} do
    assert {:ok, %FactEvent{} = event} = Turnstile.Code.publish()
    assert event.kind == :policy_version
    assert event.subject_ref == nil
    assert event.object_ref == {:policy, Turnstile.Code}
    assert event.attribute == :version
    assert event.old == nil
    assert %PolicyVersion{version: "conformance"} = event.new
    assert event.by == Subject.library()
    assert event.position == 1

    assert Turnstile.Code.publish() == {:ok, :current}
    assert Turnstile.Code.publish() == {:ok, :current}
    assert {:ok, [_one]} = Memory.read(options, 0, 10)
  end

  test "a newer version records the previous one as old" do
    assert {:ok, %FactEvent{old: nil}} = Turnstile.Code.publish()
    :ok = Binding.override(policy: Turnstile.Code.VersionTest.Later)
    assert {:ok, %FactEvent{old: "conformance", new: %PolicyVersion{version: "later"}}} = Turnstile.Code.publish()
  end

  test "in ledger mode none publish emits telemetry alone" do
    :ok = Turnstile.Test.with_config(ledger: :none)
    :telemetry.attach(inspect(self()), Version.telemetry_event(), &__MODULE__.forward/4, self())
    assert Turnstile.Code.publish() == {:ok, :telemetry}
    assert_receive {:policy_version, %{version: %PolicyVersion{version: "conformance"}, result: :telemetry}}
  after
    :telemetry.detach(inspect(self()))
  end

  test "the default version is the content hash" do
    :ok = Binding.override(policy: Turnstile.Code.VersionTest.Unversioned)

    assert Version.ref(Turnstile.Code.VersionTest.Unversioned) ==
             Version.content_hash(Turnstile.Code.VersionTest.Unversioned)
  end

  @doc false
  @spec forward([atom()], map(), map(), pid()) :: :ok
  def forward(_event, _measurements, metadata, pid) do
    send(pid, {:policy_version, metadata})
    :ok
  end

  defmodule Later do
    @moduledoc false
    use Policy, version: "later"

    role :reader, [:read]
  end

  defmodule Unversioned do
    @moduledoc false
    use Policy

    role :reader, [:read]
  end
end
