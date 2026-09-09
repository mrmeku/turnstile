defmodule ExampleRbac.Application do
  @moduledoc """
  Boot: the configuration names the adapter and the ledger mode, the
  binding names the policy and the repo, the supervisor starts the repos
  and the audit store, and the policy version is published once the tree
  is up. The test configuration leaves the repos to the ephemeral cluster,
  and with them the publish: a ledger mode writes the version as an event,
  which needs a repo to write it through.
  """

  use Application

  alias Example.Audit.Store
  alias Turnstile.Code.Binding

  @impl Application
  def start(_type, _args) do
    ledger = Application.fetch_env!(:example_rbac, :ledger)
    _config = Turnstile.Config.boot!(adapter: Turnstile.Code, ledger: ledger)
    _binding = Binding.bind!(policy: ExampleRbac.Policy, repo: Example.Repo)
    repos = repos()
    children = [{Store, name: Store, attach: true} | repos]

    with {:ok, pid} <- Supervisor.start_link(children, strategy: :one_for_one, name: ExampleRbac.Supervisor) do
      :ok = publish(repos)
      {:ok, pid}
    end
  end

  # A ledger mode writes the policy version as an event, so the publish
  # belongs to whoever starts the repos: this tree, or the test cluster.
  defp publish([]), do: :ok

  defp publish(_repos) do
    {:ok, _published} = Turnstile.Code.publish()
    :ok
  end

  defp repos do
    if Application.get_env(:example_rbac, :start_repos, true), do: [Example.Repo, Example.OwnerRepo], else: []
  end
end
