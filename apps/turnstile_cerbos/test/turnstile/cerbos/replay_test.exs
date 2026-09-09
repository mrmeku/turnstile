defmodule Turnstile.Cerbos.ReplayTest do
  use ExUnit.Case, async: true

  alias Turnstile.Answer
  alias Turnstile.Cerbos.Decisions.Line
  alias Turnstile.Cerbos.Replay
  alias Turnstile.Cerbos.Sidecar
  alias Turnstile.Cerbos.Version
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Id
  alias Turnstile.Reason
  alias Turnstile.Subject

  @cleared %{"clearance" => "cleared"}
  @reader %{"member_roles" => ["reader"]}

  test "a stored decision asked again under the version it names answers as the record does" do
    sidecar = Sidecar.replayed!(Version.to_text(Sidecar.conformance()))

    written =
      sidecar.policies
      |> Path.join("*")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()

    assert written == ["folder.yaml", "item.yaml"]

    assert {:ok, %Answer{} = allowed} = Replay.ask(sidecar.address, decision(:allow), @cleared, @reader)
    assert allowed.verdict == :allow
    assert allowed.policy_version == "conformance"
    assert allowed.reason.code == :allowed
    assert allowed.reason.rule =~ "folder"
    assert allowed.applied_position == nil

    assert {:ok, %Answer{} = denied} = Replay.ask(sidecar.address, decision(:allow), %{"clearance" => nil}, @reader)
    assert denied.verdict == :deny
    assert denied.reason.code == :deny_by_default

    line = %Line{
      number: 1,
      subject: "an-account",
      operation: "read",
      kind: "folder",
      id: "1",
      verdict: :allow,
      roles: ["user"],
      principal: @cleared,
      resource: @reader
    }

    assert {:ok, %Answer{verdict: :allow, policy_version: nil}} = Replay.ask(sidecar.address, line)
    assert {:ok, %Answer{verdict: :deny}} = Replay.ask(sidecar.address, %{line | roles: ["stranger"]})
  end

  test "a version put back takes every policy file already there out of the directory" do
    directory = Path.join([File.cwd!(), "tmp", "replay-#{System.unique_integer([:positive])}"])
    File.mkdir_p!(Path.join(directory, "nested"))
    on_exit(fn -> File.rm_rf!(directory) end)
    File.write!(Path.join(directory, "stale.yaml"), "# another version's policy\n")
    File.write!(Path.join(directory, "nested/older.yml"), "# and another\n")
    File.write!(Path.join(directory, "keep.txt"), "no policy\n")

    :ok = Replay.build!(to: directory, policies: Version.to_text([{"folder.yaml", "# the version's own\n"}]))

    assert File.read!(Path.join(directory, "folder.yaml")) == "# the version's own\n"
    refute File.exists?(Path.join(directory, "stale.yaml"))
    refute File.exists?(Path.join(directory, "nested/older.yml"))
    assert File.exists?(Path.join(directory, "keep.txt"))
  end

  test "a sidecar out of reach is an engine error naming the replay" do
    assert {:error, %Error.Engine{} = error} = Replay.ask("127.0.0.1:1", decision(:allow), @cleared, @reader)
    assert error.adapter == Turnstile.Cerbos
    assert error.operation == :replay
    assert error.detail =~ "cerbos could not be reached"
  end

  test "the options a version put back takes name the directory and the content" do
    assert Replay.options_schema().schema[:to][:required]
    assert Replay.options_schema().schema[:policies][:required]
  end

  defp decision(verdict) do
    %Decision{
      id: Id.new(),
      subject: %Subject{id: "an-account", kind: :user},
      object: {:folder, 1},
      operation: :read,
      verdict: verdict,
      reason: Reason.allowed("folder.default"),
      adapter: Turnstile.Cerbos,
      policy_version: "conformance",
      head_position: nil,
      applied_position: nil,
      operation_id: Id.new(),
      at: DateTime.utc_now()
    }
  end
end
