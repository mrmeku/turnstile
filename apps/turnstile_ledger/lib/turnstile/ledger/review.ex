defmodule Turnstile.Ledger.Review.Row do
  @moduledoc """
  One line of a review: a subject, its kind, an operation, what the subject
  may do it to, and a note. `object` and `note` are text because a review
  over a collection answers with a rule rather than a list of rows, and the
  rule is the honest answer there.
  """

  @enforce_keys [:subject, :kind, :operation, :object]
  defstruct [:subject, :kind, :operation, :object, note: nil]

  @type t :: %__MODULE__{
          subject: String.t(),
          kind: Turnstile.Subject.kind(),
          operation: atom(),
          object: String.t(),
          note: String.t() | nil
        }

  @doc "The row's fields as the table prints them, in column order."
  @spec cells(t()) :: [String.t()]
  def cells(%__MODULE__{} = row) do
    [row.subject, Atom.to_string(row.kind), Atom.to_string(row.operation), row.object, row.note || ""]
  end
end

defmodule Turnstile.Ledger.Review do
  @moduledoc """
  What `mix turnstile.review` prints. An access review is a control's
  question, AC-2's, and the answer has to come from the port rather than from
  a query someone writes by hand each quarter, or the review proves only that
  the query ran. The library owns the table; the application owns its
  population, because no library knows an application's subjects or its
  object types.

  An application implements this behaviour and names the module in its
  `mix.exs`:

      turnstile: [review: [reporter: ExampleRbac.Review]]

  `rows/1` is called with `at: nil` for today, and, when a ledger is
  configured, with `at: date` for a date the ledger covers, which is what the
  point-in-time review adds. A reporter that cannot answer for a date says so
  by raising, since a review that quietly answers for today when it was asked
  about March is worse than no review.

  The columns are subject, kind, operation, object, and note, in that order,
  padded to the widest cell, with a header naming the date reviewed. It is
  plain text on purpose: a reviewer reads it, an assessor keeps it, and a
  golden-file test in each thin application holds it to its shape.
  """

  use Boundary, top_level?: true, deps: [Turnstile], exports: [Row]

  alias Turnstile.Error
  alias Turnstile.Ledger.Review.Row

  @columns ["subject", "kind", "operation", "object", "note"]

  @doc "The rows of a review. `at` is `nil` for today, or the date the review is asked about."
  @callback rows(keyword()) :: [Row.t()]

  @doc "The column headings, in order."
  @spec columns() :: [String.t()]
  def columns, do: @columns

  @doc """
  The review as text: the reporter named in the options, called for the date
  in them, laid out as a table. Raises `Turnstile.Error.Invalid` when the
  options name no reporter.
  """
  @spec table(keyword()) :: String.t()
  def table(options) when is_list(options) do
    reporter = reporter!(options)
    at = options[:at]
    rows = reporter.rows(at: at)

    header(at, length(rows)) <> "\n\n" <> layout([@columns | Enum.map(rows, &Row.cells/1)])
  end

  defp header(nil, count), do: "who can do what, today: #{count} rows"
  defp header(%Date{} = at, count), do: "who can do what, on #{Date.to_iso8601(at)}: #{count} rows"

  defp layout(cells) do
    widths =
      cells
      |> Enum.zip_with(&Enum.map(&1, fn cell -> String.length(cell) end))
      |> Enum.map(&Enum.max/1)

    Enum.map_join(cells, "\n", &line(&1, widths))
  end

  defp line(cells, widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> String.trim_trailing()
  end

  defp reporter!(options) do
    Keyword.get(options, :reporter) ||
      raise Error.Invalid,
        what: :review,
        detail:
          "no reporter: name the module answering the review in mix.exs, " <>
            "turnstile: [review: [reporter: MyApp.Review]]"
  end
end
