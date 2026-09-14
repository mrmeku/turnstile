defmodule ExamplePostgres do
  @moduledoc """
  The example bound to row-level security: the SQL that states the
  example's rules as Postgres policies, the migrations that reassign the
  protected tables to the owner role and write those policies, the boot
  that binds the example's schemas to `Example.Repo`, and the capability
  declaration. Nothing of the domain lives here.

  The policy version is the migration number. A migration reads the
  policies it has written back and emits the version they are at; `publish/0`
  does the same from the loaded catalog, which is what the boot calls once
  the repos are started.
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
  Emit the version the database is at, from the policies the loaded catalog
  holds.
  """
  @spec publish() :: {:ok, Turnstile.PolicyVersion.t()}
  def publish do
    %Catalog{} = catalog = Turnstile.Postgres.load!()
    {:ok, config} = Config.resolve()
    fields = [at: config.clock.()] ++ published(catalog.version)

    Version.publish(Version.of(Turnstile.Postgres, catalog.policies, fields))
  end

  @doc """
  The fields a published version carries beside its policies and the moment
  it was published at, which the caller supplies: the configured clock from
  the boot, and the migration's own default where a migration publishes
  before there is a configuration to read.
  """
  @spec published(String.t()) :: keyword()
  def published(version) when is_binary(version) do
    [
      version: version,
      author: @author,
      approval: @approval,
      content_bytes: @content_bytes
    ]
  end
end
