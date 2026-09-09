defmodule ExampleFga.Application do
  @moduledoc """
  Boot: the configuration names the server, the store, and the ledger, the
  binding names the repo the checkpoint is read through, the model file, the
  mapping, and the guard, the supervisor starts the repos and the projector,
  and the model is published as a policy version once the tree is up.

  The projector is the process that drains the ledger into the store on its
  interval. It starts here rather than in a test, because a test drives
  `c:Turnstile.Projection.drain_once/1` itself and a process draining beside it
  would read the same ledger from a connection of its own. The test
  configuration therefore leaves the repos to the ephemeral cluster and the
  projector to the tests, and with them the publish, which a ledger mode
  writes as an event and so needs a repo to write through.
  """

  use Application

  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Projector

  @impl Application
  def start(_type, _args) do
    _config =
      Turnstile.Config.boot!(
        adapter: {Turnstile.Fga, entry()},
        ledger: Application.fetch_env!(:example_fga, :ledger)
      )

    _binding =
      Binding.bind!(
        repo: Example.Repo,
        model: ExampleFga.model(),
        mapping: ExampleFga.TupleMapping,
        guard: ExampleFga.Guard,
        author: ExampleFga.author(),
        approval: ExampleFga.approval()
      )

    children = started()

    with {:ok, pid} <- Supervisor.start_link(children, strategy: :one_for_one, name: ExampleFga.Supervisor) do
      :ok = publish(children)
      {:ok, pid}
    end
  end

  # Where the server is, which store it keeps this application's tuples in,
  # and how often the projector drains into it.
  defp entry do
    [
      endpoint: Application.fetch_env!(:example_fga, :endpoint),
      store_id: Application.fetch_env!(:example_fga, :store_id),
      drain_interval: Application.fetch_env!(:example_fga, :drain_interval)
    ]
  end

  # A ledger mode writes the policy version as an event, so the publish
  # belongs to whoever starts the repos: this tree, or the test cluster.
  defp publish([]), do: :ok

  defp publish(_children) do
    {:ok, _published} = Turnstile.Fga.publish()
    :ok
  end

  defp started do
    if Application.get_env(:example_fga, :start_repos, true) do
      [Example.Repo, Example.OwnerRepo, Projector.Scheduler]
    else
      []
    end
  end
end
