defmodule Example do
  @moduledoc """
  The example application: controlled unclassified information, as a
  library application. `domain/` is what the example knows: the schemas,
  which declare object types and fact mappings, the control vocabulary,
  rule C4's arithmetic, and the re-authentication window. The contexts
  call the port and write through the seam, and the consumer maps the
  library's events to the shape a security log takes. No adapter is named
  here; a thin application binds one.
  """

  use Boundary,
    deps: [
      Turnstile,
      Ecto,
      Ecto.Adapters.Postgres,
      Ecto.Adapters.SQL,
      Ecto.Migration,
      NimbleOptions
    ],
    exports: [
      Application.Accounts,
      Application.Documents,
      Application.Documents.BannerViolation,
      Application.Documents.OverrideRefused,
      Application.Proposals,
      Application.Review,
      Domain.AccountRole,
      Domain.Agency,
      Domain.Assignment,
      Domain.Banner,
      Domain.Category,
      Domain.Controls,
      Domain.Document,
      Domain.Marking,
      Domain.Office,
      Domain.OfficeRole,
      Domain.OverrideReport,
      Domain.Portion,
      Domain.Program,
      Domain.Proposal,
      Domain.Sessions,
      Domain.User,
      Migrations.Domain,
      OwnerRepo,
      Repo,
      Siem
    ]

  @schemas [
    Example.Domain.Agency,
    Example.Domain.Office,
    Example.Domain.Program,
    Example.Domain.Category,
    Example.Domain.User,
    Example.Domain.AccountRole,
    Example.Domain.Assignment,
    Example.Domain.OfficeRole,
    Example.Domain.Document,
    Example.Domain.Marking,
    Example.Domain.Portion,
    Example.Domain.Proposal,
    Example.Domain.OverrideReport
  ]

  @doc """
  Every schema of the example, in the order its tables are created, which
  is the order a migration creates them in and the reverse of the order it
  drops them in.
  """
  @spec schemas() :: [module()]
  def schemas, do: @schemas
end
