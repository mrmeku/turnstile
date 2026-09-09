defmodule ExampleFga.Rules do
  @moduledoc """
  What the scenarios need from this binding: a store of each test's own, a
  tightened model published for the calling process, the boot model pinned
  again, the boot model published into a ledger a committed test has emptied,
  and a question asked again under a version and a state a replay names.

  The store is per test because it is the engine's own copy of the facts: two
  tests writing tuples into one store would read each other's, whatever the
  database does with their rows. Creating it is what `setup/1` is for, and
  which model id the test is pinned to differs by tier. A committed test
  empties the ledger and then publishes the boot model itself, so the id it
  asks under is the id the version event carries and a scenario setting the
  two beside each other compares equal ids. A sandboxed test keeps the boot
  event the run committed, whose digest a publish would find current, so the
  model is written into the new store directly and that id is pinned.

  A rule change here is a model of its own: models are immutable and named by
  id, so publishing one changes nothing that is already stored and a question
  moves to it by being asked under another id. Restoring is therefore pinning
  the boot id again, with nothing to wait for. The tightened text keeps every
  type and every relation of the boot model, since the tuples in the store
  were written against it and a write after the change is validated against
  the latest model there is.

  A replay is the heavier one. The state is a copy loaded into a server of the
  test's own with the in-memory datastore: the ledger is folded to the
  position the decision names, the mapping turns that fold into tuples, and
  the model of the version is published into a store nothing else reads.
  Nothing of the application's tables reaches that answer, so a scenario needs
  no rows put back.
  """

  @behaviour Example.Scenarios.Rules

  use Boundary,
    top_level?: true,
    deps: [
      Example.Scenarios,
      ExampleFga,
      ExampleFga.Tightened,
      Turnstile,
      Turnstile.Fga,
      Turnstile.Ledger.Replay,
      Turnstile.Test
    ]

  alias Example.Scenarios.Rules
  alias ExampleFga.Tightened
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client.Http
  alias Turnstile.Fga.Model
  alias Turnstile.Ledger.Replay
  alias Turnstile.PolicyVersion
  alias Turnstile.Test

  @boot {__MODULE__, :boot_model}

  @impl Rules
  def setup(tags) when is_map(tags) do
    server = Test.Fga.info()
    {:ok, store} = Http.create_store(server.address, name())
    :ok = Test.with_config(adapter: {Fga, endpoint: server.address, store_id: store})
    stored(server, store, tags[:committed])
  end

  @impl Rules
  def publish_tightened do
    :ok = Binding.override(model: Tightened.written())

    with {:ok, %FactEvent{new: %PolicyVersion{} = version}} <- Fga.publish() do
      :ok = pinned(version.version)
      {:ok, version}
    end
  end

  @impl Rules
  def restore do
    :ok = Binding.override(model: ExampleFga.model())
    pinned(booted())
  end

  @impl Rules
  def publish_boot do
    {:ok, %FactEvent{new: %PolicyVersion{version: model}}} = Fga.publish()
    boot(model)
  end

  @impl Rules
  def replay(%Replay{} = replay, fun) when is_function(fun, 0) do
    server = Test.Fga.start_supervised!([])
    {:ok, loaded} = Fga.Replay.build(build(server, replay))
    entry = [endpoint: server.address, store_id: loaded.store, model_id: loaded.model]

    Test.with_config([adapter: {Fga, entry}], fun)
  end

  # A committed test publishes the boot model itself, through `publish_boot/0`,
  # and pins what that answers. A sandboxed test has the store write the model
  # of the boot text, because the ledger's boot event already carries its
  # digest and a publish would answer that the ledger is current.
  defp stored(_server, _store, true), do: :ok

  defp stored(server, store, _sandboxed) do
    {:ok, model} = Http.write_model(server.address, store, Model.read!(ExampleFga.model()))
    boot(model)
  end

  defp build(server, %Replay{} = replay) do
    [
      client: Http,
      endpoint: server.address,
      model: text(replay),
      mapping: ExampleFga.TupleMapping,
      ledger: ledger(),
      to: replay.position
    ]
  end

  # The model text of the version, which the event carries by value under the
  # cap. Above it the event names the file instead, and getting that text back
  # is a checkout of the commit the file was at.
  defp text(%Replay{policy_version: %PolicyVersion{content: content}}) when is_binary(content), do: content

  defp text(%Replay{policy_version: %PolicyVersion{} = version}) do
    raise %Error.Unsupported{
      adapter: Fga,
      feature: :replay,
      note: "version #{version.version} carries #{version.pointer} rather than its text"
    }
  end

  # The model every question of this test is asked under, kept beside the
  # endpoint and the store the entry already names.
  defp pinned(model) do
    {Fga, options} = adapter()

    Test.with_config(adapter: {Fga, Keyword.put(options, :model_id, model)})
  end

  defp boot(model) do
    :ok = pinned(model)
    _previous = Process.put(@boot, model)
    :ok
  end

  defp booted do
    Process.get(@boot) || raise "no boot model for this test: setup/1 pins one before anything is published"
  end

  defp adapter do
    {:ok, config} = Config.resolve()

    Config.adapter(config)
  end

  defp ledger do
    {:ok, config} = Config.resolve()

    config.ledger
  end

  defp name, do: "example-fga-#{System.unique_integer([:positive])}"
end
