defmodule ExampleFga.Application do
  @moduledoc """
  Boot: the configuration names the server, the store, and the ledger, the
  binding names the repo the markers and the tables are read through, the
  model file, the mapping, and the guard, the handler that writes a marker
  for every change is attached, the supervisor starts the repos and the
  runner that delivers those markers, and the model is published as a policy
  version once the tree is up.

  The runner is the process that drains the outbox into the store on its
  interval. It starts here rather than in a test, because a test settles the
  store itself and a process draining beside it would read the same markers
  from a connection of its own. The test configuration therefore leaves the
  repos to the ephemeral cluster and the runner to the tests, and with them
  the publish, which a ledger mode writes as an event and so needs a repo to
  write through.

  The handler is attached either way. A marker is written on the connection
  the change was made on, so what it needs is a binding and the write's own
  transaction rather than a tree of this application's.
  """

  use Application

  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Outbox

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

    :ok = Outbox.attach()
    children = started()

    with {:ok, pid} <- Supervisor.start_link(children, strategy: :one_for_one, name: ExampleFga.Supervisor) do
      :ok = publish(children)
      {:ok, pid}
    end
  end

  # Where the server is and which store it keeps this application's tuples
  # in. How far the drain has got is the cursor's, in the database, rather
  # than anything the configuration carries.
  defp entry do
    [
      endpoint: Application.fetch_env!(:example_fga, :endpoint),
      store_id: Application.fetch_env!(:example_fga, :store_id)
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
      [Example.Repo, Example.OwnerRepo, drain()]
    else
      []
    end
  end

  defp drain do
    {Turnstile.Relay, runners: [[name: Outbox.runner(), repo: Example.Repo, job: Outbox]]}
  end
end
