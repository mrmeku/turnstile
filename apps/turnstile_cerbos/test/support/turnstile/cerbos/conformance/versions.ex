defmodule Turnstile.Cerbos.Conformance.Versions do
  @moduledoc """
  The change-management artifact of the Cerbos adapter: tightening writes
  a folder policy whose read admits a reader's membership alone over the
  one the sidecar reads, binds the commit the tightened policy is at, and
  publishes it; restoring puts the boot policy back, binds the boot
  commit, and asks the sidecar until the boot policy answers again. The
  sidecar watches its policy directory, so a swap is in force once it has
  read the file, which is the propagation the laws measure.
  """

  @behaviour Turnstile.Conformance.Versions

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Client
  alias Turnstile.Cerbos.Propagation
  alias Turnstile.Cerbos.Request
  alias Turnstile.Cerbos.Version
  alias Turnstile.Config
  alias Turnstile.Conformance.Versions
  alias Turnstile.Test

  @path "folder.yaml"
  @swapped {__MODULE__, :swapped}
  @deadline 30_000

  @tightened """
  # The neutral fixture's rule for a folder, tightened: a reader's
  # membership alone admits a read, so the granted editor is denied.
  apiVersion: api.cerbos.dev/v1
  resourcePolicy:
    version: default
    resource: folder
    rules:
      - actions: ["read"]
        effect: EFFECT_ALLOW
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            all:
              of:
                - expr: request.principal.attr.clearance == "cleared"
                - expr: '"reader" in request.resource.attr.member_roles'
      - actions: ["edit"]
        effect: EFFECT_ALLOW
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            all:
              of:
                - expr: request.principal.attr.clearance == "cleared"
                - expr: '"editor" in request.resource.attr.member_roles'
      - actions: ["share"]
        effect: EFFECT_ALLOW
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            all:
              of:
                - expr: request.principal.attr.clearance == "cleared"
                - expr: size(request.resource.attr.member_roles) > 1
  """

  @impl Versions
  def event, do: Version.telemetry_event()

  @impl Versions
  def tighten do
    {:ok, %Binding{} = binding} = Binding.resolve()
    previous = Propagation.swap!(binding.policies, [{@path, @tightened}])
    Process.put(@swapped, {binding.policies, previous})
    :ok = Binding.override(commit: "conformance-tightened")
    Turnstile.Cerbos.publish()
  end

  @impl Versions
  def restore do
    {directory, previous} = Process.delete(@swapped)
    :ok = Propagation.restore!(directory, previous)
    :ok = Binding.override(commit: "conformance")
    true = Test.poll(&editor_reads?/0, @deadline)
    :ok
  end

  # The boot policy is back once a cleared editor may read a folder again,
  # asked of the sidecar with the attributes given inline, so no row need
  # exist for the question.
  defp editor_reads? do
    {:ok, %Config{} = config} = Config.resolve()
    {Turnstile.Cerbos, options} = Config.adapter(config)
    principal = %{id: "turnstile.restore", roles: ["user"], attr: %{clearance: "cleared"}}
    resource = %{kind: "folder", id: "0", attr: %{member_roles: ["editor"]}}

    case Client.check_resources(options[:address], Request.logged(principal, resource, ["read"])) do
      {:ok, %{"results" => [%{"actions" => %{"read" => "EFFECT_ALLOW"}}]}} -> true
      _other -> false
    end
  end
end
