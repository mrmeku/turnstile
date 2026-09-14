defmodule Example do
  @moduledoc """
  The example application: controlled unclassified information, as a
  library application. The schemas declare object types and fact mappings,
  the contexts call the port and write through the seam, and the consumer
  maps the library's events to the shape a security log takes. What
  decides without touching the world is under `core/`: the queries each
  context runs and the mapping to OCSF. The web layer is `ExampleWeb`,
  which reaches the contexts and nothing under them. No adapter is named
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
      Accounts,
      AccountRole,
      Agency,
      Assignment,
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
      Program,
      Proposal,
      Proposals,
      Repo,
      Review,
      Sessions,
      Siem,
      User
    ]

  @schemas [
    Example.Agency,
    Example.Office,
    Example.Program,
    Example.Category,
    Example.User,
    Example.AccountRole,
    Example.Assignment,
    Example.OfficeRole,
    Example.Document,
    Example.Marking,
    Example.Portion,
    Example.Proposal,
    Example.OverrideReport
  ]

  @doc """
  Every schema of the example, in the order its tables are created, which
  is the order a migration creates them in and the reverse of the order it
  drops them in.
  """
  @spec schemas() :: [module()]
  def schemas, do: @schemas
end
