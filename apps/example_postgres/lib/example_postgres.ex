defmodule ExamplePostgres do
  @moduledoc """
  The example bound to row-level security: the SQL that states the
  example's rules as Postgres policies, the migrations that reassign the
  protected tables to the owner role and write those policies, the boot
  that binds the example's schemas to `Example.Repo`, and the capability
  declaration. Nothing of the domain lives here.

  The policy version is the migration number. A migration runs before the
  application is up, so it has no repo to write a ledger event through;
  the version reaches the ledger from `publish/0`, which the boot calls
  once the repos are started and which answers `{:ok, :current}` when the
  ledger already names the version the database is at.
  """

  use Boundary,
    deps: [Example, Turnstile, Turnstile.Postgres, Ecto],
    exports: [Application, Capabilities, Policies]

  alias Turnstile.Config
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Version

  @author "example_postgres"
  @approval "the migration under review"
  @content_bytes 65_536

  @doc "Who wrote the rules, as the record of a policy version carries it."
  @spec author() :: String.t()
  def author, do: @author

  @doc "What approved them, as the record of a policy version carries it."
  @spec approval() :: String.t()
  def approval, do: @approval

  @doc """
  Publish the version the database is at into the ledger the configuration
  names, from the policies the loaded catalog holds.
  """
  @spec publish() :: {:ok, Turnstile.PolicyVersion.t()}
  def publish do
    %Catalog{} = catalog = Turnstile.Postgres.load!()
    {:ok, config} = Config.resolve()
    version = Version.of(Turnstile.Postgres, catalog.policies, published(catalog.version))
    {:ok, _result} = Version.publish(version, config.ledger)
    {:ok, version}
  end

  @doc "The fields a published version carries beside its policies."
  @spec published(String.t()) :: keyword()
  def published(version) when is_binary(version) do
    [
      version: version,
      author: @author,
      approval: @approval,
      at: DateTime.utc_now(),
      content_bytes: @content_bytes
    ]
  end
end
