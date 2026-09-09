defmodule Example.Review do
  @moduledoc """
  Access review (AC-2, AC-6(5), AC-6(7)): who can do what today, per
  agency, and every privileged account. The port's `review` answers under
  one record for the reviewer; the report is text a task prints and a test
  compares. The reviewer is administrative: the rows the review ranges over
  are read under a declared exemption, and every verdict comes from the
  port, so the report says what the adapter enforces.

  This module is also the reporter `mix turnstile.review` prints, which the
  thin applications name in their `mix.exs`. The task asks two different
  questions and this module answers each from the place that can answer it.
  Today's rows come from the port, one per subject, operation, and document
  the subject may act on, with every privileged account and the roles it
  holds. The rows of a past date come from the ledger, whose fold at that
  date holds the grants that stood then; the tables cannot answer for a
  date, and where the configuration names no ledger the review says so by
  raising rather than answering for today.

  A review of `change_marking` asks what a role may do rather than what one
  session may do, so the call carries a re-authentication as of the clock
  the configuration names: without it every marking row would be absent for
  a reason that is the session's and not the role's.
  """

  @behaviour Turnstile.Ledger.Review

  import Ecto.Query, only: [from: 2]

  alias Example.Accounts
  alias Example.Agency
  alias Example.Document
  alias Example.Documents
  alias Example.Repo
  alias Example.User
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.Ledger.Replay
  alias Turnstile.Ledger.Review.Row
  alias Turnstile.Object
  alias Turnstile.Subject

  @review {:exempt, "access review: the population the reviewer ranges over"}

  @reviewer %Subject{id: "turnstile.review", kind: :privileged}

  @typedoc "Per subject, per operation, the ids of the documents the subject may act on."
  @type permissions :: %{Subject.t() => %{atom() => [integer()]}}

  @doc "Who can read which documents of an agency, by subject, over every account."
  @spec readers(Subject.t(), Agency.t(), keyword()) :: %{Subject.t() => [integer()]}
  def readers(%Subject{} = reviewer, %Agency{id: agency_id}, opts \\ []) when is_list(opts) do
    reviewer
    |> Turnstile.review(subjects(), :read, documents(agency_id), opts)
    |> Map.new(fn {subject, refs} -> {subject, ids(refs)} end)
  end

  @doc "Every permission every account holds on the documents of an agency, by operation."
  @spec permissions(Subject.t(), Agency.t(), keyword()) :: permissions()
  def permissions(%Subject{} = reviewer, %Agency{id: agency_id}, opts \\ []) when is_list(opts) do
    subjects = subjects()
    documents = documents(agency_id)

    Documents.operations()
    |> Enum.flat_map(&reviewed(reviewer, subjects, &1, documents, opts))
    |> Enum.group_by(fn {subject, _op, _ids} -> subject end, fn {_subject, op, ids} -> {op, ids} end)
    |> Map.new(fn {subject, entries} -> {subject, Map.new(entries)} end)
  end

  @doc """
  The report: readers per agency, then every operation of each account
  that holds any permission, then privileged accounts.
  """
  @spec report(Subject.t(), keyword()) :: String.t()
  def report(%Subject{} = reviewer, opts \\ []) when is_list(opts) do
    agencies = Repo.all(agencies(), turnstile: @review)

    lines =
      Enum.flat_map(agencies, fn agency ->
        ["agency #{agency.name}"] ++ reader_lines(reviewer, agency, opts) ++ permission_lines(reviewer, agency, opts)
      end)

    Enum.join(lines ++ privileged_lines(), "\n") <> "\n"
  end

  @doc """
  The rows the task prints: today's from the port, a past date's from the
  fold of the ledger stopped at the end of that date. Raises
  `Turnstile.Error.Unsupported` when a date is asked for and the
  configuration names no ledger.
  """
  @impl Turnstile.Ledger.Review
  def rows(options) when is_list(options) do
    case Keyword.get(options, :at) do
      nil -> today()
      %Date{} = date -> as_of(date)
    end
  end

  @doc "The subject the task's review is recorded under: the reviewer names the record, not the reader."
  @spec reviewer() :: Subject.t()
  def reviewer, do: @reviewer

  defp today do
    {:ok, config} = Config.resolve()
    opts = [facts: %{reauthenticated_at: config.clock.now()}]
    agencies = Repo.all(agencies(), turnstile: @review)
    Enum.flat_map(agencies, &agency_rows(&1, opts)) ++ privileged_rows()
  end

  defp agency_rows(agency, opts) do
    @reviewer
    |> permissions(agency, opts)
    |> Enum.sort_by(fn {subject, _by_operation} -> subject.id end)
    |> Enum.flat_map(fn {subject, by_operation} -> subject_rows(subject, by_operation, agency) end)
  end

  defp subject_rows(subject, by_operation, agency) do
    for operation <- Documents.operations(), id <- by_operation[operation] || [] do
      %Row{
        subject: subject.id,
        kind: subject.kind,
        operation: operation,
        object: "document:#{id}",
        note: "agency #{agency.name}"
      }
    end
  end

  defp privileged_rows do
    for {user, roles} <- Accounts.privileged(), role <- roles do
      %Row{subject: user.id, kind: :privileged, operation: role, object: "-", note: "person #{user.person_id}"}
    end
  end

  # The grants the fold holds at the end of the date, which is what the
  # review of a past date is: one row per relationship, under the kind the
  # fact mapping names a subject by.
  defp as_of(%Date{} = date) do
    {:ok, replay} = Replay.at(ledger!(date), DateTime.new!(date, ~T[23:59:59.999999]))

    replay.fold.facts
    |> Enum.filter(&granted?/1)
    |> Enum.sort()
    |> Enum.map(&granted_row(&1, replay))
  end

  defp granted?({{{:user, _id}, {_type, _object_id}, nil}, value}), do: not is_nil(value)
  defp granted?({_key, _value}), do: false

  defp granted_row({{{:user, id}, {type, object_id}, nil}, role}, replay) do
    %Row{
      subject: id,
      kind: :user,
      operation: role,
      object: "#{type}:#{object_id}",
      note: "as of position #{replay.position}"
    }
  end

  defp ledger!(date) do
    case Config.resolve() do
      {:ok, %Config{ledger: :none} = config} -> raise Error.Unsupported, unsupported(config, date)
      {:ok, %Config{ledger: ledger}} -> ledger
    end
  end

  defp unsupported(%Config{} = config, date) do
    {adapter, _options} = Config.adapter(config)

    [
      adapter: adapter,
      feature: :point_in_time_review,
      note:
        "the boot configuration names no ledger, and the review of #{Date.to_iso8601(date)} " <>
          "is the fold of one; the tables hold today"
    ]
  end

  defp reader_lines(reviewer, agency, opts) do
    reviewer
    |> readers(agency, opts)
    |> Enum.sort_by(fn {subject, _ids} -> subject.id end)
    |> Enum.map(fn {subject, ids} -> "  #{subject.id} reads #{listed(ids)}" end)
  end

  defp permission_lines(reviewer, agency, opts) do
    reviewer
    |> permissions(agency, opts)
    |> Enum.reject(fn {_subject, by_op} -> Enum.all?(by_op, fn {_operation, ids} -> ids == [] end) end)
    |> Enum.sort_by(fn {subject, _by_op} -> subject.id end)
    |> Enum.flat_map(fn {subject, by_op} ->
      for operation <- Documents.operations() do
        "  #{subject.id} may #{operation} #{listed(by_op[operation] || [])}"
      end
    end)
  end

  defp listed(ids), do: "[#{Enum.join(ids, ", ")}]"

  defp privileged_lines do
    ["privileged accounts"] ++
      Enum.map(Accounts.privileged(), fn {user, roles} ->
        "  #{user.id} (person #{user.person_id}) holds [#{Enum.join(roles, ", ")}]"
      end)
  end

  defp agencies, do: from(a in Agency, order_by: a.id)

  defp subjects do
    query = from(u in User, order_by: u.id, select: {u.id, u.kind})

    query
    |> Repo.all()
    |> Enum.map(fn {id, kind} -> %Subject{id: id, kind: kind} end)
  end

  defp documents(agency_id) do
    query =
      from(d in Document,
        join: o in assoc(d, :designating_office),
        where: o.agency_id == ^agency_id,
        order_by: d.id,
        select: d.id
      )

    query
    |> Repo.all(turnstile: @review)
    |> Enum.map(&%Object{type: :document, id: &1})
  end

  defp ids(refs) when is_list(refs) do
    refs
    |> Enum.map(fn {:document, id} -> id end)
    |> Enum.sort()
  end

  defp reviewed(reviewer, subjects, operation, documents, opts) do
    reviewer
    |> Turnstile.review(subjects, operation, documents, opts)
    |> Enum.map(fn {subject, refs} -> {subject, operation, ids(refs)} end)
  end
end
