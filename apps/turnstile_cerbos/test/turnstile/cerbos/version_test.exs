defmodule Turnstile.Cerbos.VersionTest do
  use ExUnit.Case, async: true

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Conformance.Attributes
  alias Turnstile.Cerbos.Sidecar
  alias Turnstile.Cerbos.Version
  alias Turnstile.Config
  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Memory
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject
  alias Turnstile.Test
  alias Turnstile.TestRepos.Sandboxed

  # Each test gets a sidecar of its own over a copy of the conformance
  # policies, because a test here writes into the policy directory it reads.
  setup do
    sidecar = Sidecar.own!()
    agent = start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})
    :ok = Test.with_config(adapter: {Turnstile.Cerbos, address: sidecar.address}, ledger: {Memory, agent: agent})

    :ok =
      Binding.override(
        repo: Sandboxed,
        attributes: Attributes,
        policies: sidecar.policies,
        commit: "conformance",
        author: "turnstile_cerbos",
        approval: "the conformance suite",
        decision_log: sidecar.audit_log
      )

    {:ok, sidecar: sidecar, ledger: {Memory, agent: agent}}
  end

  test "the version is the commit, and the content is the policy files each preceded by its path" do
    {:ok, config} = Config.resolve()
    {:ok, binding} = Binding.resolve()
    at = DateTime.utc_now()

    assert {:ok, %PolicyVersion{} = version} = Version.of(Turnstile.Cerbos, binding, config, at)
    assert version.adapter == Turnstile.Cerbos
    assert version.version == "conformance"
    assert version.author == "turnstile_cerbos"
    assert version.approval == "the conformance suite"
    assert version.at == at
    assert version.content =~ "# turnstile-policy: folder.yaml"
    assert version.content =~ "# turnstile-policy: item.yaml"
    assert version.content =~ "resource: folder"
    assert version.pointer == nil
    assert version.content_hash == Version.content_hash(version.content)
    assert String.length(version.content_hash) == 64
  end

  test "over the content cap the version carries a pointer to the directory and the commit", ctx do
    :ok = Test.with_config(caps: [policy_content_bytes: 8])
    {:ok, config} = Config.resolve()
    {:ok, binding} = Binding.resolve()

    assert {:ok, %PolicyVersion{} = version} = Version.of(Turnstile.Cerbos, binding, config, DateTime.utc_now())
    assert version.content == nil
    assert version.pointer == "policies in #{ctx.sidecar.policies} at conformance"
    assert String.length(version.content_hash) == 64
  end

  test "the text carries the files back, by path, in the order it holds them" do
    {:ok, binding} = Binding.resolve()

    assert {:ok, files} = Version.files(binding)
    assert Enum.map(files, &elem(&1, 0)) == ["folder.yaml", "item.yaml"]
    assert Version.from_text(Version.to_text(files)) == files
  end

  test "a text with a trailing marker and no body carries no file back" do
    assert Version.from_text("# turnstile-policy: folder.yaml") == []
  end

  test "a directory that changed without a commit is a hash that no longer matches", ctx do
    {:ok, binding} = Binding.resolve()
    assert {:ok, before} = Version.content(binding)

    File.write!(Path.join(ctx.sidecar.policies, "folder.yaml"), "# nothing the sidecar reads as a policy\n")

    assert {:ok, changed} = Version.content(binding)
    assert Version.ref(binding) == "conformance"
    refute Version.content_hash(changed) == Version.content_hash(before)
  end

  test "a policy directory that holds nothing is a version with an empty content" do
    :ok = Binding.override(policies: Path.join(File.cwd!(), "tmp/no-policies-here"))
    {:ok, binding} = Binding.resolve()

    assert Version.content(binding) == {:ok, ""}
  end

  test "publish appends the commit once and emits one policy version event", ctx do
    {Memory, options} = ctx.ledger
    :telemetry.attach(inspect(self()), Version.telemetry_event(), &__MODULE__.forward/4, self())

    assert {:ok, %FactEvent{} = event} = Turnstile.Cerbos.publish()
    assert event.kind == :policy_version
    assert event.subject_ref == nil
    assert event.object_ref == {:policy, Turnstile.Cerbos}
    assert event.attribute == :version
    assert event.old == nil
    assert %PolicyVersion{version: "conformance"} = event.new
    assert event.by == Subject.library()

    assert_receive {:policy_version, %{version: %PolicyVersion{version: "conformance"}, result: %FactEvent{}}}
    refute_receive {:policy_version, _later}

    assert Turnstile.Cerbos.publish() == {:ok, :current}
    assert {:ok, [_one]} = Memory.read(options, 0, 10)
  after
    :telemetry.detach(inspect(self()))
  end

  test "a later commit records the one before it as old" do
    assert {:ok, %FactEvent{old: nil}} = Turnstile.Cerbos.publish()
    :ok = Binding.override(commit: "later")

    assert {:ok, %FactEvent{old: "conformance", new: %PolicyVersion{version: "later"}}} = Turnstile.Cerbos.publish()
  end

  test "in ledger mode none publish emits telemetry and appends nothing" do
    :ok = Test.with_config(ledger: :none)
    :telemetry.attach(inspect(self()), Version.telemetry_event(), &__MODULE__.forward/4, self())

    assert Turnstile.Cerbos.publish() == {:ok, :telemetry}
    assert_receive {:policy_version, %{result: :telemetry}}
  after
    :telemetry.detach(inspect(self()))
  end

  @doc false
  @spec forward([atom()], map(), map(), pid()) :: :ok
  def forward(_event, _measurements, metadata, pid) do
    send(pid, {:policy_version, metadata})
    :ok
  end
end
