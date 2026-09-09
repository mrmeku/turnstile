defmodule Example.Review do
  @moduledoc """
  Access review (AC-2, AC-6(5), AC-6(7)): who can do what today, per
  agency, and every privileged account. The port's `review` answers under
  one record for the reviewer; the report is text a task prints and a test
  compares. The reviewer is administrative: the rows the review ranges over
  are read under a declared exemption, and every verdict comes from the
  port, so the report says what the adapter enforces.
  """

  import Ecto.Query, only: [from: 2]

  alias Example.Accounts
  alias Example.Agency
  alias Example.Document
  alias Example.Documents
  alias Example.Repo
  alias Example.User
  alias Turnstile.Object
  alias Turnstile.Subject

  @review {:exempt, "access review: the population the reviewer ranges over"}

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

  @doc "The report: readers per agency, then permissions per account, then privileged accounts."
  @spec report(Subject.t(), keyword()) :: String.t()
  def report(%Subject{} = reviewer, opts \\ []) when is_list(opts) do
    agencies = Repo.all(agencies(), turnstile: @review)

    lines =
      Enum.flat_map(agencies, fn agency ->
        ["agency #{agency.name}"] ++ reader_lines(reviewer, agency, opts) ++ permission_lines(reviewer, agency, opts)
      end)

    Enum.join(lines ++ privileged_lines(), "\n") <> "\n"
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
    |> Enum.sort_by(fn {subject, _by_op} -> subject.id end)
    |> Enum.flat_map(fn {subject, by_op} ->
      for operation <- Documents.operations(), ids = by_op[operation], ids != [] do
        "  #{subject.id} may #{operation} #{listed(ids)}"
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
