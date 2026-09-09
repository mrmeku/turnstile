defmodule Turnstile.Fga.VersionTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Model
  alias Turnstile.Fga.Version
  alias Turnstile.Ledger.Memory
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject
  alias Turnstile.Test
  alias Turnstile.TestRepos.Sandboxed

  @model "priv/conformance/model.fga"

  # A fake on an agent of the test's own is the server here, because what a
  # publication does to a server is one call, and the id it answers with is
  # what the ledger records.
  setup do
    agent = start_supervised!(Fake)
    {:ok, store} = Fake.create_store(agent, "version")
    ledger = start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})

    :ok =
      Test.with_config(
        adapter: {Fga, endpoint: agent, store_id: store, client: Fake},
        ledger: {Memory, agent: ledger}
      )

    :ok =
      Binding.override(
        repo: Sandboxed,
        model: @model,
        mapping: Mapping,
        author: "turnstile_fga",
        approval: "the conformance suite"
      )

    {:ok, agent: agent, store: store, ledger: {Memory, agent: ledger}}
  end

  test "the version is the model id, and the content is the text the model file holds" do
    at = DateTime.utc_now()
    text = File.read!(@model)

    assert %PolicyVersion{} = version = Version.of(Fga, "model-1", text, options(at))
    assert version.adapter == Fga
    assert version.version == "model-1"
    assert version.author == "turnstile_fga"
    assert version.approval == "the conformance suite"
    assert version.at == at
    assert version.content == text
    assert version.content =~ "type folder"
    assert version.pointer == nil
    assert version.content_hash == Version.content_hash(text)
    assert String.length(version.content_hash) == 64
  end

  test "over the content cap the version carries a pointer to the file the model is in" do
    text = File.read!(@model)

    assert %PolicyVersion{} = version = Version.of(Fga, "model-1", text, options(DateTime.utc_now(), 8))
    assert version.content == nil
    assert version.pointer == "the model in priv/conformance/model.fga"
    assert version.content_hash == Version.content_hash(text)
  end

  test "publish writes the model once and appends the version once", context do
    {Memory, options} = context.ledger
    :telemetry.attach(inspect(self()), Version.telemetry_event(), &__MODULE__.forward/4, self())

    assert {:ok, %FactEvent{} = event} = Fga.publish()
    assert event.kind == :policy_version
    assert event.subject_ref == nil
    assert event.object_ref == {:policy, Fga}
    assert event.attribute == :version
    assert event.old == nil
    assert %PolicyVersion{version: "model-1", adapter: Fga} = event.new
    assert event.by == Subject.library()
    assert models(context.agent) == [Model.read!(@model)]

    assert_receive {:policy_version, %{adapter: Fga, hash: hash, result: %FactEvent{}}}
    assert hash == Version.content_hash(File.read!(@model))
    refute_receive {:policy_version, _later}

    assert Fga.publish() == {:ok, :current}
    assert {:ok, [_one]} = Memory.read(options, 0, 10)
    assert length(models(context.agent)) == 1
  after
    :telemetry.detach(inspect(self()))
  end

  test "a text the ledger's latest does not carry is published again, over the id before it", context do
    assert {:ok, %FactEvent{old: nil, new: %PolicyVersion{version: "model-1"}}} = Fga.publish()
    :ok = Binding.override(model: changed())

    assert {:ok, %FactEvent{old: "model-1", new: %PolicyVersion{version: "model-2"}}} = Fga.publish()
    assert length(models(context.agent)) == 2
  end

  test "a publication answering that the ledger is current says so in the telemetry" do
    :telemetry.attach(inspect(self()), Version.telemetry_event(), &__MODULE__.forward/4, self())
    assert {:ok, %FactEvent{}} = Fga.publish()

    assert Fga.publish() == {:ok, :current}
    assert_receive {:policy_version, %{result: %FactEvent{}}}
    assert_receive {:policy_version, %{result: :current}}
  after
    :telemetry.detach(inspect(self()))
  end

  test "a model file that is not there publishes nothing" do
    :ok = Binding.override(model: "priv/conformance/absent.fga")

    assert {:error, %Error.Invalid{what: :binding} = error} = Fga.publish()
    assert error.detail =~ "priv/conformance/absent.fga could not be read"
  end

  test "a configuration naming another adapter publishes nothing under this one", context do
    :ok = Test.with_config(adapter: Turnstile.Adapter.Fake)

    assert {:error, %Error.Invalid{what: :model} = error} = Fga.publish()
    assert error.detail == "Turnstile.Adapter.Fake is the configured adapter, not Turnstile.Fga"
    assert models(context.agent) == []
  end

  test "in ledger mode none there is nothing to publish into" do
    :ok = Test.with_config(adapter: Turnstile.Adapter.Fake, ledger: :none)

    assert Fga.publish() ==
             {:error,
              %Error.Unsupported{
                adapter: Fga,
                feature: :ledger_mode_none,
                note: "there is nothing to publish into"
              }}
  end

  @doc false
  @spec forward([atom()], map(), map(), pid()) :: :ok
  def forward(_event, _measurements, metadata, pid) do
    send(pid, {:policy_version, metadata})
    :ok
  end

  defp options(at, content_bytes \\ 65_536) do
    [
      author: "turnstile_fga",
      approval: "the conformance suite",
      at: at,
      path: @model,
      content_bytes: content_bytes
    ]
  end

  defp models(agent) do
    for {:write_model, model} <- Fake.calls(agent), do: model
  end

  # A model that differs from the bound one by a relation, in a file of this
  # test's own, so a second publication has a text of its own to carry.
  defp changed do
    path = Path.join([File.cwd!(), "tmp", "model-#{System.unique_integer([:positive])}.fga"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, String.replace(File.read!(@model), "define can_edit: editor", "define can_edit: editor or reader"))
    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
