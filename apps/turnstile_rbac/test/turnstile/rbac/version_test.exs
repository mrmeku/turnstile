defmodule Turnstile.Rbac.VersionTest do
  use ExUnit.Case, async: true

  alias Turnstile.Config
  alias Turnstile.PolicyVersion
  alias Turnstile.Rbac.Binding
  alias Turnstile.Rbac.Conformance.Predicates
  alias Turnstile.Rbac.Conformance.Roles
  alias Turnstile.Rbac.Policy
  alias Turnstile.Rbac.Version
  alias Turnstile.TestRepos.Sandboxed

  setup do
    :ok = Turnstile.Test.with_config(adapter: Turnstile.Rbac)
    :ok = Binding.override(policy: Roles, repo: Sandboxed)
  end

  test "the version carries the commit, the hash of the rule modules, and the role table as data" do
    {:ok, config} = Config.resolve()
    at = DateTime.utc_now()
    version = Version.of(Turnstile.Rbac, Roles, config, at)

    assert %PolicyVersion{adapter: Turnstile.Rbac, version: "conformance", author: "turnstile_rbac"} = version
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
    version = Version.of(Turnstile.Rbac, Roles, config, DateTime.utc_now())
    assert version.content == nil
    assert version.pointer == "modules #{inspect(Predicates)}, #{inspect(Roles)}"
  end

  test "publish emits the bound policy's version, once per call" do
    :telemetry.attach(inspect(self()), Version.telemetry_event(), &__MODULE__.forward/4, self())

    assert {:ok, %PolicyVersion{} = version} = Turnstile.Rbac.publish()
    assert version.adapter == Turnstile.Rbac
    assert version.version == "conformance"
    assert version.content =~ "  reader: read\n"

    assert_receive {:policy_version, %{version: ^version}}
    refute_receive {:policy_version, _later}
  after
    :telemetry.detach(inspect(self()))
  end

  test "a policy that names another version publishes under that one" do
    assert {:ok, %PolicyVersion{version: "conformance"}} = Turnstile.Rbac.publish()
    :ok = Binding.override(policy: Turnstile.Rbac.VersionTest.Later)

    assert {:ok, %PolicyVersion{version: "later"}} = Turnstile.Rbac.publish()
  end

  test "the default version is the content hash" do
    :ok = Binding.override(policy: Turnstile.Rbac.VersionTest.Unversioned)

    assert Version.ref(Turnstile.Rbac.VersionTest.Unversioned) ==
             Version.content_hash(Turnstile.Rbac.VersionTest.Unversioned)
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
