defmodule Example do
  @moduledoc """
  The example application: controlled unclassified information, as a
  library application. The schemas declare object types and fact mappings,
  the contexts call the port and write through the seam, the web layer
  identifies the caller and nothing else, and the audit store chains the
  decision events. No adapter is named here; a thin application binds one.
  """

  use Boundary,
    deps: [Turnstile, Ecto, Ecto.Adapters.Postgres, Ecto.Adapters.SQL, Ecto.Migration, Phoenix, Plug, NimbleOptions],
    exports: [
      Accounts,
      AccountRole,
      Agency,
      Assignment,
      Audit,
      Audit.Chain,
      Audit.Record,
      Audit.Store,
      DocumentController,
      Category,
      Controls,
      Document,
      Documents,
      Documents.BannerViolation,
      Documents.OverrideRefused,
      Marking,
      Migrations.Domain,
      Office,
      OfficeRole,
      OverrideReport,
      OwnerRepo,
      Portion,
      Plug.Identity,
      Program,
      ProposalController,
      Proposal,
      Proposals,
      Repo,
      Review,
      Router,
      Sessions,
      User
    ]
end
