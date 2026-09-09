defmodule ExampleCerbos.Application do
  @moduledoc """
  Boot: the configuration names the sidecar's address and the ledger mode,
  the binding names the repo, the attribute declarations, the policy
  directory, and the commit that directory is at, the supervisor starts the
  repos and the audit store, and the commit is published as a policy version
  once the tree is up. The test configuration leaves the repos to the
  ephemeral cluster, and with them the publish: a ledger mode writes the
  version as an event, which needs a repo to write it through.
  """

  use Application

  alias Example.Audit.Store
  alias Turnstile.Cerbos.Binding

  @impl Application
  def start(_type, _args) do
    ledger = Application.fetch_env!(:example_cerbos, :ledger)
    address = Application.fetch_env!(:example_cerbos, :address)
    _config = Turnstile.Config.boot!(adapter: {Turnstile.Cerbos, address: address}, ledger: ledger)

    _binding =
      Binding.bind!(
        repo: Example.Repo,
        attributes: ExampleCerbos.Attributes,
        policies: policies(),
        commit: Application.fetch_env!(:example_cerbos, :commit),
        author: ExampleCerbos.author(),
        approval: ExampleCerbos.approval()
      )

    repos = repos()
    children = [{Store, name: Store, attach: true} | repos]

    with {:ok, pid} <- Supervisor.start_link(children, strategy: :one_for_one, name: ExampleCerbos.Supervisor) do
      :ok = publish(repos)
      {:ok, pid}
    end
  end

  # The configured directory is where the sidecar reads its policies, given
  # relative to this application's priv directory unless it is absolute, so
  # a release finds the files where they were installed.
  defp policies do
    configured = Application.fetch_env!(:example_cerbos, :policies)

    case Path.type(configured) do
      :absolute -> configured
      _relative -> Application.app_dir(:example_cerbos, configured)
    end
  end

  # A ledger mode writes the policy version as an event, so the publish
  # belongs to whoever starts the repos: this tree, or the test cluster.
  defp publish([]), do: :ok

  defp publish(_repos) do
    {:ok, _published} = Turnstile.Cerbos.publish()
    :ok
  end

  defp repos do
    if Application.get_env(:example_cerbos, :start_repos, true), do: [Example.Repo, Example.OwnerRepo], else: []
  end
end
