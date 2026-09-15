defmodule ExampleCerbos.Application do
  @moduledoc """
  Boot: the configuration names the sidecar's address, the binding names the
  repo, the attribute declarations, the policy directory, and the commit that
  directory is at, the supervisor starts the repos and the consumer of the
  events, and the commit is emitted as a policy version once the tree is up.
  The test configuration leaves the repos to the ephemeral cluster, and with
  them the publish, so a run has one policy-version event rather than two.
  """

  use Application

  alias Example.Infrastructure.Repo
  alias Example.Infrastructure.Siem
  alias Turnstile.Cerbos.Binding

  @impl Application
  def start(_type, _args) do
    address = Application.fetch_env!(:example_cerbos, :address)
    _config = Turnstile.Config.boot!(adapter: {Turnstile.Cerbos, address: address})

    _binding =
      Binding.bind!(
        repo: Repo,
        attributes: ExampleCerbos.Attributes,
        policies: policies(),
        commit: Application.fetch_env!(:example_cerbos, :commit),
        author: ExampleCerbos.author(),
        approval: ExampleCerbos.approval()
      )

    repos = repos()
    children = [{Siem, name: Siem, attach: true} | repos]

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

  # The publish belongs to whoever starts the repos: this tree, or the test
  # cluster.
  defp publish([]), do: :ok

  defp publish(_repos) do
    {:ok, _published} = Turnstile.Cerbos.publish()
    :ok
  end

  defp repos do
    if Application.get_env(:example_cerbos, :start_repos, true), do: [Repo, Example.Infrastructure.OwnerRepo], else: []
  end
end
