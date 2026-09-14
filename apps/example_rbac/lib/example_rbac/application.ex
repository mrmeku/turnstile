defmodule ExampleRbac.Application do
  @moduledoc """
  Boot: the configuration names the adapter, the binding names the policy
  and the repo, the supervisor starts the repos and the consumer of the
  events, and the policy version is emitted once the tree is up. The test
  configuration leaves the repos to the ephemeral cluster, and with them the
  publish, so a run has one policy-version event rather than two.
  """

  use Application

  alias Example.Siem
  alias Turnstile.Code.Binding

  @impl Application
  def start(_type, _args) do
    _config = Turnstile.Config.boot!(adapter: Turnstile.Code)
    _binding = Binding.bind!(policy: ExampleRbac.Policy, repo: Example.Repo)
    repos = repos()
    children = [{Siem, name: Siem, attach: true} | repos]

    with {:ok, pid} <- Supervisor.start_link(children, strategy: :one_for_one, name: ExampleRbac.Supervisor) do
      :ok = publish(repos)
      {:ok, pid}
    end
  end

  # The publish belongs to whoever starts the repos: this tree, or the test
  # cluster.
  defp publish([]), do: :ok

  defp publish(_repos) do
    {:ok, _published} = Turnstile.Code.publish()
    :ok
  end

  defp repos do
    if Application.get_env(:example_rbac, :start_repos, true), do: [Example.Repo, Example.OwnerRepo], else: []
  end
end
