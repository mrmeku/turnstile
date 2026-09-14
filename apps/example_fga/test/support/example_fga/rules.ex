defmodule ExampleFga.Rules do
  @moduledoc """
  What the scenarios need from this binding: a store of each test's own, a
  tightened model published for the calling process, and the boot model
  pinned again.

  The store is per test because it is the engine's own copy of the facts: two
  tests writing tuples into one store would read each other's, whatever the
  database does with their rows. Creating it is what `setup/1` is for, and the
  boot model is written into it there, so every question the test asks is
  asked under a model of its own.

  A rule change here is a model of its own: models are immutable and named by
  id, so publishing one changes nothing that is already stored and a question
  moves to it by being asked under another id. Restoring is therefore pinning
  the boot id again, with nothing to wait for. The tightened text keeps every
  type and every relation of the boot model, since the tuples in the store
  were written against it and a write after the change is validated against
  the latest model there is.
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
      Turnstile.Test
    ]

  alias Example.Scenarios.Rules
  alias ExampleFga.Tightened
  alias Turnstile.Config
  alias Turnstile.Dev
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client.Http
  alias Turnstile.Fga.Model
  alias Turnstile.Fga.Version
  alias Turnstile.PolicyVersion
  alias Turnstile.Test

  @boot {__MODULE__, :boot_model}

  @impl Rules
  def setup(_tags) do
    server = Dev.Fga.info()
    {:ok, store} = Http.create_store(server.address, name())
    :ok = Test.with_config(adapter: {Fga, endpoint: server.address, store_id: store})
    {:ok, model} = Http.write_model(server.address, store, Model.read!(ExampleFga.model()))
    boot(model)
  end

  @impl Rules
  def version_event, do: Version.telemetry_event()

  @impl Rules
  def publish_tightened do
    :ok = Binding.override(model: Tightened.written())

    with {:ok, %PolicyVersion{} = version} <- Fga.publish() do
      :ok = pinned(version.version)
      {:ok, version}
    end
  end

  @impl Rules
  def restore do
    :ok = Binding.override(model: ExampleFga.model())
    pinned(booted())
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

  defp name, do: "example-fga-#{System.unique_integer([:positive])}"
end
