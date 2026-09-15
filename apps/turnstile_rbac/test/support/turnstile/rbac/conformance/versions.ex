defmodule Turnstile.Rbac.Conformance.Versions do
  @moduledoc """
  The change-management artifact of RBAC in code: tightening binds
  `Turnstile.Rbac.Conformance.Tightened` in place of the boot role table
  and publishes it, and restoring binds the boot table again. A policy in
  code is in force the moment it is bound, so neither waits.
  """

  @behaviour Turnstile.Conformance.Versions

  alias Turnstile.Conformance.Versions
  alias Turnstile.Rbac.Binding
  alias Turnstile.Rbac.Conformance.Roles
  alias Turnstile.Rbac.Conformance.Tightened
  alias Turnstile.Rbac.Version

  @impl Versions
  def event, do: Version.telemetry_event()

  @impl Versions
  def tighten do
    :ok = Binding.override(policy: Tightened)
    Turnstile.Rbac.publish()
  end

  @impl Versions
  def restore, do: Binding.override(policy: Roles)
end
