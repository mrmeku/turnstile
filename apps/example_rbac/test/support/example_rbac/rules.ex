defmodule ExampleRbac.Rules do
  @moduledoc """
  The policy operations the scenarios need from this binding: a tightened
  policy, under which a program member no longer reads, bound and published
  for the calling process; the boot policy restored; and the boot policy
  published again, which is what the boot itself does.
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

  @impl Rules
  def publish_boot do
    {:ok, _published} = Turnstile.Code.publish()
    :ok
  end
end
