defmodule Mix.Tasks.Turnstile.Review do
  @shortdoc "Prints who can do what, today or on a date the ledger covers"
  @moduledoc """
  Prints the access review the application's reporter answers, as a table.

      mix turnstile.review
      mix turnstile.review --at 2026-03-01

  The task reads the reporter from the `:turnstile` key of the application's
  `mix.exs` project configuration:

      turnstile: [review: [reporter: ExampleRbac.Review]]

  Without `--at` the review is of today. With it, the review is of the end of
  that date, which is the fold of the ledger stopped there. What a mode can
  claim is the ledger's to state and the reporter's to honour: a reporter
  with no ledger behind it raises rather than answering for today when it
  was asked about March.
  """

  use Boundary, top_level?: true, deps: [Mix, Turnstile.Ledger.Review]
  use Mix.Task

  alias Turnstile.Ledger.Review

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    config = Mix.Project.config()
    options = Keyword.get(config[:turnstile] || [], :review, [])
    table = Review.table(Keyword.put(options, :at, at(args)))
    Mix.shell().info(table)
  end

  defp at([]), do: nil
  defp at(["--at", date]), do: date!(date)

  defp at(args) do
    Mix.raise("mix turnstile.review takes --at <date> or nothing, and was given: #{Enum.join(args, " ")}")
  end

  defp date!(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> Mix.raise("mix turnstile.review --at takes a date as YYYY-MM-DD, and was given: #{date}")
    end
  end
end
