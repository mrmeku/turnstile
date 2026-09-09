defmodule Turnstile.Ledger.Reconcile do
  @moduledoc """
  The ledger against the tables. The seam records every fact write that goes
  through it, so the fold of the ledger and the facts the tables hold are the
  same thing read two ways; anything that changed a fact table another way
  leaves them apart, and that difference is drift. A patch applied with
  `psql`, a cascade nobody meant, a job that writes with the owner role: none
  of them can be prevented by a library, and all of them can be found.

  Both reads run through the owner-role repo the ledger's options name, on
  one connection, so an out-of-band write that has committed is visible to
  both. A fact write that commits between the two reads shows up as a
  difference the next pass does not repeat, which is why drift is a report
  on an interval (`Turnstile.Ledger.Reconcile.Scheduler`) rather than an
  alarm on one reading.

  Drift is `Turnstile.Projection.Drift`: `missing` is what the ledger's fold
  says is true and the tables do not have, `extra` what the tables have and
  the fold does not, each as `{fact key, value}`, and `checked_to` is the
  head the comparison was made at.
  """

  use Boundary, top_level?: true, deps: [Ecto, Turnstile, Turnstile.Ledger.Ecto, Turnstile.Ledger.Reader]

  alias Turnstile.Error
  alias Turnstile.Ledger
  alias Turnstile.Projection.Drift
  alias Turnstile.Repo
  alias Turnstile.Schema
  alias Turnstile.Subject

  @exemption {:exempt, :library}

  @doc """
  Compare the fold of the ledger with the facts the given schemas hold, and
  answer the drift. Schemas that declare no fact are ignored.
  """
  @spec run(keyword(), [module()]) :: {:ok, Drift.t()} | {:error, Error.Engine.t()}
  def run(ledger_options, schemas) when is_list(ledger_options) and is_list(schemas) do
    options = through_owner(ledger_options)

    with {:ok, head} <- Ledger.Ecto.head(options),
         {:ok, events} <- Ledger.Reader.all({Ledger.Ecto, options}) do
      {:ok, compare(Ledger.Fold.to(events, head).facts, facts(options, schemas), head)}
    end
  end

  @doc "The facts the tables hold now, keyed as the fold keys them."
  @spec facts(keyword(), [module()]) :: %{Ledger.Fold.key() => term()}
  def facts(ledger_options, schemas) when is_list(ledger_options) and is_list(schemas) do
    repo = Ledger.Ecto.repo(ledger_options)
    stamp = %{by: Subject.library(), operation_id: "reconcile", at: DateTime.from_unix!(0)}

    events =
      Enum.flat_map(Enum.filter(schemas, &Schema.fact_schema?/1), fn schema ->
        schema
        |> repo.all(turnstile: @exemption)
        |> Enum.flat_map(&Repo.Facts.events(schema, nil, &1, stamp))
      end)

    Ledger.Fold.fold(events).facts
  end

  defp compare(folded, held, head) do
    %Drift{
      missing: Enum.sort(Enum.reject(folded, fn {key, value} -> Map.get(held, key) == value end)),
      extra: Enum.sort(Enum.reject(held, fn {key, value} -> Map.get(folded, key) == value end)),
      checked_to: head
    }
  end

  # Genesis writes at position zero and reconcile reads out of band, both
  # through the owner role, which is the one role the grants let write and
  # read every event.
  defp through_owner(ledger_options) do
    Keyword.put(ledger_options, :repo, Keyword.fetch!(ledger_options, :owner_repo))
  end
end
