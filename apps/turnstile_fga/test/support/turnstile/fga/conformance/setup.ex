defmodule Turnstile.Fga.Conformance.Setup do
  @moduledoc """
  What the case templates of this package are run under: a sandbox checkout,
  a fake with a store of the test's own, the configuration entry pointing at
  it, and the binding naming the repo of the checkout and the conformance
  mapping. A template calls this first in every test, before
  it writes a population.
  """

  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Model
  alias Turnstile.Test
  alias Turnstile.Test.Sandbox

  @model "priv/conformance/model.fga"

  @doc "Check the repo out, stand a fake up, and bind this process to both."
  @spec setup(module(), map()) :: :ok
  def setup(repo, tags) do
    :ok = Sandbox.setup(repo, tags)
    agent = ExUnit.Callbacks.start_supervised!(Fake)
    {:ok, store} = Fake.create_store(agent, "case")
    {:ok, model} = Fake.write_model(agent, store, Model.read!(@model))

    :ok = Test.with_config(adapter: {Fga, endpoint: agent, store_id: store, client: Fake, model_id: model})

    Binding.override(repo: repo, model: @model, mapping: Mapping)
  end
end
