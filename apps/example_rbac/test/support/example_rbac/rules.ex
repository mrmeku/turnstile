defmodule ExampleRbac.Rules do
  @moduledoc """
  The two policy operations the scenarios need from this binding: a
  tightened policy, under which a program member no longer reads, bound and
  published for the calling process; and the boot policy restored.
  """

  @behaviour Example.Scenarios.Rules

  use Boundary, top_level?: true, deps: [ExampleRbac, ExampleRbac.Tightened, Turnstile, Turnstile.Code]

  alias Example.Scenarios.Rules
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Version

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
end
