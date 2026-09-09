defmodule ExampleCerbos.Tightened do
  @moduledoc """
  The document policy with one clause removed: a program member holds
  `read_redacted` and no longer `read`. What the revocation and change
  scenarios publish, and the commit they publish it as.

  The text is here whole rather than derived from the boot policy, because a
  policy file is what the sidecar reads and a rule change is a new file. The
  file it replaces is the one `path/0` names, under the directory the
  binding is serving.
  """

  use Boundary, top_level?: true, deps: []

  @path "document.yaml"
  @commit "policies-0002-tightened"

  @document """
  # The boot document policy with the program member's `read` taken out: the
  # two read actions no longer share one rule, and `read_redacted` is the one
  # that keeps every role. Everything else is the boot policy unchanged.
  apiVersion: api.cerbos.dev/v1
  resourcePolicy:
    version: default
    resource: document
    rules:
      - actions: ["read"]
        effect: EFFECT_ALLOW
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            any:
              of:
                - expr: '"lead" in request.resource.attr.program_roles'
                - expr: '"designator" in request.resource.attr.office_roles'
                - expr: '"approver" in request.resource.attr.office_roles'

      - actions: ["read_redacted"]
        effect: EFFECT_ALLOW
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            any:
              of:
                - expr: '"lead" in request.resource.attr.program_roles'
                - expr: '"member" in request.resource.attr.program_roles'
                - expr: '"designator" in request.resource.attr.office_roles'
                - expr: '"approver" in request.resource.attr.office_roles'

      - actions: ["read"]
        effect: EFFECT_DENY
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            all:
              of:
                - expr: '"federal_only" in request.resource.attr.effective_controls'
                - expr: 'request.principal.attr.employment != "federal"'
                - any:
                    of:
                      - expr: request.resource.attr.decontrol == null
                      - expr: request.resource.attr.decontrol > request.principal.attr.environment.now

      - actions: ["read"]
        effect: EFFECT_DENY
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            all:
              of:
                - expr: '"no_foreign" in request.resource.attr.effective_controls'
                - expr: '!(request.principal.attr.nationality in request.resource.attr.agency_nationalities)'
                - any:
                    of:
                      - expr: request.resource.attr.decontrol == null
                      - expr: request.resource.attr.decontrol > request.principal.attr.environment.now

      - actions: ["read"]
        effect: EFFECT_DENY
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            all:
              of:
                - expr: '"releasable_to" in request.resource.attr.effective_controls'
                - expr: '!(request.principal.attr.nationality in request.resource.attr.releasable_to)'
                - any:
                    of:
                      - expr: request.resource.attr.decontrol == null
                      - expr: request.resource.attr.decontrol > request.principal.attr.environment.now

      - actions: ["read"]
        effect: EFFECT_DENY
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            all:
              of:
                - expr: '"named_list" in request.resource.attr.effective_controls'
                - expr: '!(request.principal.id in request.resource.attr.listed)'
                - any:
                    of:
                      - expr: request.resource.attr.decontrol == null
                      - expr: request.resource.attr.decontrol > request.principal.attr.environment.now

      - actions: ["change_marking", "set_decontrol", "decontrol"]
        effect: EFFECT_ALLOW
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            all:
              of:
                - expr: '"designator" in request.resource.attr.office_roles'
                - expr: request.principal.attr.environment.reauthenticated_at != null
                - expr: >-
                    timestamp(request.principal.attr.environment.reauthenticated_at)
                    <= timestamp(request.principal.attr.environment.now)
                - expr: >-
                    timestamp(request.principal.attr.environment.reauthenticated_at)
                    >= timestamp(request.principal.attr.environment.now) - duration("900s")

      - actions: ["propose_marking"]
        effect: EFFECT_ALLOW
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            expr: '"designator" in request.resource.attr.office_roles'
  """

  @doc "The path of the policy file this replaces, relative to the policy directory."
  @spec path() :: Path.t()
  def path, do: @path

  @doc "The commit the tightened policies are published as."
  @spec commit() :: String.t()
  def commit, do: @commit

  @doc "The tightened document policy, as the file text."
  @spec document() :: String.t()
  def document, do: @document
end
