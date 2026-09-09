defmodule ExamplePostgres.Application do
  @moduledoc """
  Boot: the configuration names the adapter and the ledger mode, the
  binding names the repo and the schemas whose tables the policies protect,
  the supervisor starts the repos and the audit store, and the policies and
  their version are read from the database once the tree is up. The test
  configuration leaves the repos to the ephemeral cluster, and with them
  the read: the catalog is a query, which needs a repo to run through.
  """

  use Application

  alias Example.Audit.Store
  alias ExamplePostgres.Policies
  alias Turnstile.Postgres.Binding

  @impl Application
  def start(_type, _args) do
    ledger = Application.fetch_env!(:example_postgres, :ledger)
    _config = Turnstile.Config.boot!(adapter: Turnstile.Postgres, ledger: ledger)
    _binding = Binding.bind!(repo: Example.Repo, schemas: Policies.schemas())
    repos = repos()
    children = [{Store, name: Store, attach: true} | repos]

    with {:ok, pid} <- Supervisor.start_link(children, strategy: :one_for_one, name: ExamplePostgres.Supervisor) do
      :ok = ready(repos)
      {:ok, pid}
    end
  end

  # The catalog read and the publish belong to whoever starts the repos:
  # this tree, or the test cluster.
  defp ready([]), do: :ok

  defp ready(_repos) do
    _catalog = Turnstile.Postgres.load!()
    {:ok, _published} = ExamplePostgres.publish()
    :ok
  end

  defp repos do
    if Application.get_env(:example_postgres, :start_repos, true), do: [Example.Repo, Example.OwnerRepo], else: []
  end
end
