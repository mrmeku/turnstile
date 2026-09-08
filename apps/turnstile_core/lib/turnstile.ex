defmodule Turnstile do
  @moduledoc """
  The port: the one place an application asks whether a subject may perform
  an operation on an object, and the contracts every adapter, ledger, and
  projection implements.

  This module is the top-layer boundary. Everything under `Turnstile` that is
  not `Turnstile.Test` or `Turnstile.Conformance` belongs to it, and it may
  reach `Ecto` and `NimbleOptions` and nothing from `ecto_sql` or `postgrex`:
  the port decides, it does not query.
  """

  use Boundary,
    deps: [Ecto, NimbleOptions],
    check: [apps: [:ecto_sql, :postgrex]],
    exports: [
      Adapter,
      Adapter.Fake,
      Answer,
      Capabilities,
      Clock,
      Clock.System,
      Config,
      Decision,
      Environment,
      Error.Engine,
      Error.Invalid,
      Error.NotAuthorized,
      Error.Unmediated,
      Error.Unsupported,
      Exemption,
      Explanation,
      FactEvent,
      Id,
      Ledger,
      Ledger.Memory,
      Object,
      PolicyVersion,
      Projection,
      Projection.Drain,
      Projection.Drift,
      Reason,
      Schema,
      Schema.Fact,
      Schema.Relationship,
      Scope,
      Subject
    ]
end
