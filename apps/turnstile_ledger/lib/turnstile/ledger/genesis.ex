defmodule Turnstile.Ledger.Genesis do
  @moduledoc """
  The ledger's first entries: every fact the tables hold today, written as
  an event at position zero, before any fact write goes through the seam.
  Without it the ledger would describe a system that began empty, and a fold
  of it would lack every grant made before the table existed; with it the
  fold at the head is the tables, which is what reconcile compares and what
  replay depends on. Replay before genesis is not available by construction,
  and position zero is what says so.

  Genesis runs once, from the migration that creates the events table, and
  refuses to run twice. Its events share one `operation_id`, the sentence
  "backfilled from tables on ⟨date⟩ by ⟨migration⟩", so an investigator who
  pulls the operation gets the backfill and nothing else. Every write goes
  through the owner-role repo the ledger's options name, because the
  application role may insert an event and nothing else.

      defmodule ExampleRbac.Repo.Migrations.Genesis do
        use Ecto.Migration

        def up do
          {:ok, _count} =
            Turnstile.Ledger.Genesis.run(
              [repo: ExampleRbac.Repo, owner_repo: ExampleRbac.OwnerRepo],
              [ExampleRbac.Assignment, ExampleRbac.User],
              migration: __MODULE__
            )
        end

        def down, do: :ok
      end

  Before it writes anything it runs the catalog check
  (`Turnstile.Ledger.Catalog`), because a foreign key that cascades into a
  fact schema would change a fact with no event to say so, and a ledger that
  begins beside such a key is wrong from its first entry.
  """

  use Boundary,
    top_level?: true,
    deps: [Ecto, Turnstile, Turnstile.Ledger.Catalog, Turnstile.Ledger.Dialect, Turnstile.Ledger.Ecto]

  alias Turnstile.Error
  alias Turnstile.Ledger
  alias Turnstile.Repo
  alias Turnstile.Schema
  alias Turnstile.Subject

  @exemption {:exempt, :library}

  @schema NimbleOptions.new!(
            migration: [
              type: {:or, [:atom, :string]},
              required: true,
              doc: "The migration doing the backfill, named in the stamp every event carries."
            ],
            clock: [
              type: :atom,
              doc:
                "The `Turnstile.Clock` the stamp's date and every event's time come from; " <>
                  "`Turnstile.Clock.System` when absent, named when this runs rather than when it compiles."
            ]
          )

  @doc """
  Write every current fact of the given schemas at position zero, through
  the ledger's owner repo, and answer how many events that was. Schemas that
  declare no fact are ignored, so a caller may pass every schema it has.
  Options: #{NimbleOptions.docs(@schema)}
  """
  @spec run(keyword(), [module()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.Invalid.t() | Error.Engine.t()}
  def run(ledger_options, schemas, options \\ []) when is_list(ledger_options) and is_list(schemas) do
    options = NimbleOptions.validate!(Keyword.put_new(options, :clock, Turnstile.Clock.System), @schema)
    repo = owner_repo!(ledger_options)
    dialect = Ledger.Ecto.dialect(ledger_options)
    at = options[:clock].now()

    with :ok <- Ledger.Catalog.check(repo, schemas, dialect),
         :ok <- empty!(repo) do
      {:ok, backfill(repo, Enum.filter(schemas, &Schema.fact_schema?/1), dialect, stamp(options, at))}
    end
  end

  @doc "The sentence every event of a backfill carries as its `operation_id`."
  @spec note(module() | String.t(), DateTime.t()) :: String.t()
  def note(migration, %DateTime{} = at) do
    "backfilled from tables on #{Date.to_iso8601(DateTime.to_date(at))} by #{name(migration)}"
  end

  defp backfill(repo, schemas, dialect, stamp) do
    written =
      repo.transaction(fn ->
        Enum.reduce(schemas, 0, fn schema, count ->
          events = events(repo, schema, stamp)
          :ok = Ledger.Ecto.write(repo, events, dialect.fact_insert_batch())
          count + length(events)
        end)
      end)

    unwrap(written)
  end

  defp events(repo, schema, stamp) do
    schema
    |> repo.all(turnstile: @exemption)
    |> Enum.flat_map(&Repo.Facts.events(schema, nil, &1, stamp))
    |> Enum.map(&%{&1 | position: 0})
  end

  defp stamp(options, at) do
    %{by: Subject.library(), operation_id: note(options[:migration], at), at: at}
  end

  defp empty!(repo) do
    case Ledger.Ecto.count(repo) do
      0 ->
        :ok

      held ->
        {:error,
         %Error.Invalid{
           what: :genesis,
           detail:
             "the ledger already holds #{held} events; genesis backfills the tables once, " <>
               "from the migration that creates the table, and never beside events it did not write"
         }}
    end
  end

  defp owner_repo!(ledger_options) do
    Keyword.get(ledger_options, :owner_repo) ||
      raise Error.Invalid,
        what: :genesis,
        detail: "the ledger's options name no owner_repo, and the application role may not write at position zero"
  end

  defp name(migration) when is_atom(migration), do: inspect(migration)
  defp name(migration) when is_binary(migration), do: migration

  defp unwrap({:ok, written}), do: written

  # Only `Turnstile.Ledger.Ecto.write/3` runs inside, and it raises rather
  # than answering an error, so a rollback here is the database refusing.
  defp unwrap({:error, reason}) do
    raise Error.Engine, adapter: __MODULE__, operation: :genesis, detail: "the backfill rolled back: #{inspect(reason)}"
  end
end
