defmodule ExampleRbac.Rules do
  @moduledoc """
  The policy operations the scenarios need from this binding: a tightened
  policy, under which a program member no longer reads, bound and published
  for the calling process; the boot policy restored; and the event a
  published version is emitted on.
  """

  @behaviour Example.Scenarios.Rules

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Fixture,
      Example.Scenarios,
      ExampleRbac,
      ExampleRbac.Tightened,
      Turnstile,
      Turnstile.Rbac
    ]

  alias Example.Scenarios.Rules
  alias Turnstile.Rbac.Binding
  alias Turnstile.Rbac.Version

  @impl Rules
  def version_event, do: Version.telemetry_event()

  @impl Rules
  def publish_tightened do
    :ok = Binding.override(policy: ExampleRbac.Tightened)

    Turnstile.Rbac.publish()
  end

  @impl Rules
  def restore, do: Binding.override(policy: ExampleRbac.Policy)
end
