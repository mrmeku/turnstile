defmodule Mix.Tasks.Turnstile.Review do
  @shortdoc "Prints who can do what today"
  @moduledoc """
  Prints the access review the application's reporter answers, as a table.

      mix turnstile.review

  The task reads the reporter from the `:turnstile` key of the application's
  `mix.exs` project configuration:

      turnstile: [review: [reporter: ExampleRbac.Review]]

  It reviews today. Reviewing a date the ledger covers is what point-in-time
  review adds, and until then the task takes no arguments rather than
  accepting one it would answer wrongly.
  """

  use Boundary, top_level?: true, deps: [Mix, Turnstile.Ledger.Review]
  use Mix.Task

  alias Turnstile.Ledger.Review

  @requirements ["app.start"]

  @impl Mix.Task
  def run([]) do
    config = Mix.Project.config()
    options = Keyword.get(config[:turnstile] || [], :review, [])
    table = Review.table(Keyword.put(options, :at, nil))
    Mix.shell().info(table)
  end

  def run(_args) do
    Mix.raise("mix turnstile.review takes no arguments; reviewing a date arrives with point-in-time review")
  end
end
