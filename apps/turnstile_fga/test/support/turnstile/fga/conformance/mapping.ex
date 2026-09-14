defmodule Turnstile.Fga.Conformance.Mapping do
  @moduledoc """
  The neutral fixture as tuples, read from its tables. A membership of an
  account on a folder is the account holding the membership's role on that
  folder, and an account's clearance is the account holding `member` on the
  clearance as an entity of its own, because a graph compares by walking
  rather than by equality.

  A folder tuple carries the account's clearance as the condition
  `while_cleared`, so a clearance that changes is the same tuple key with
  another value on it: the drain deletes that tuple and writes it again, in
  two calls. That is the shape a control with a parameter has, in the
  fixture's own terms. A membership whose account has no clearance states no
  tuple at all, because the model admits a role on a folder under that
  condition alone and a tuple carrying none of it is refused.

  A change to a membership names the folder it sits on, which the change
  carries where the write moved it and the row itself carries where the
  write left it alone. A change to an account's clearance names the
  clearances it moved between and every folder the account holds a
  membership on, which the change does not carry at all.
  """

  @behaviour Turnstile.Fga.TupleMapping

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Fga.TupleMapping
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership

  @condition "while_cleared"
  @exemption {:exempt, "conformance mapping"}

  @impl TupleMapping
  def object_types, do: ["clearance", "folder"]

  @impl TupleMapping
  def objects(repo, "folder") do
    for id <- all(repo, from(folder in Folder, select: folder.id)), do: "folder:#{id}"
  end

  def objects(repo, "clearance") do
    query = from(account in Account, where: not is_nil(account.clearance), distinct: true, select: account.clearance)

    for value <- all(repo, query), do: "clearance:#{value}"
  end

  def objects(_repo, _type), do: []

  @impl TupleMapping
  def changed(repo, %{schema: Membership, target: {_kind, id}, changes: changes}) do
    folders = Enum.uniq(moved(changes, :folder_id) ++ folder_of(repo, id))

    for folder <- folders, do: "folder:#{folder}"
  end

  def changed(repo, %{schema: Account, target: {_kind, account}, changes: changes}) do
    clearances = for value <- moved(changes, :clearance), is_binary(value), do: "clearance:#{value}"

    Enum.uniq(clearances ++ folders_of(repo, account))
  end

  def changed(_repo, %{}), do: []

  @impl TupleMapping
  def tuples(repo, object) do
    case String.split(object, ":", parts: 2) do
      ["folder", id] -> folder_tuples(repo, id)
      ["clearance", value] -> clearance_tuples(repo, value)
      _other -> []
    end
  end

  # A role on a folder is restricted to a cleared account, so the tuple has a
  # condition to carry only once the account has a clearance: an account with
  # none holds nothing on the folder yet.
  defp folder_tuples(repo, id) do
    query =
      from(membership in Membership,
        join: account in Account,
        on: account.id == membership.account_id,
        where: membership.folder_id == ^id and not is_nil(account.clearance) and not is_nil(membership.role),
        select: {membership.account_id, membership.role, account.clearance}
      )

    for {account, role, clearance} <- all(repo, query) do
      %TupleKey{
        user: "user:#{account}",
        relation: to_string(role),
        object: "folder:#{id}",
        condition: condition(clearance)
      }
    end
  end

  defp clearance_tuples(repo, value) do
    query = from(account in Account, where: account.clearance == ^value, select: account.id)

    for account <- all(repo, query) do
      %TupleKey{user: "user:#{account}", relation: "member", object: "clearance:#{value}"}
    end
  end

  # The folder a membership sits on now, for a change that left the column
  # alone: a delete carries both of its own, and a row that is gone answers
  # nothing here.
  defp folder_of(repo, id) do
    query = from(membership in Membership, where: membership.id == ^id, select: membership.folder_id)

    all(repo, query)
  end

  defp folders_of(repo, account) do
    query = from(membership in Membership, where: membership.account_id == ^account, select: membership.folder_id)

    for folder <- all(repo, query), do: "folder:#{folder}"
  end

  defp moved(changes, column) do
    case Map.fetch(changes, column) do
      {:ok, {was, now}} -> Enum.reject([was, now], &is_nil/1)
      :error -> []
    end
  end

  defp condition(clearance), do: %Condition{name: @condition, context: %{"clearance" => clearance}}

  defp all(repo, query), do: repo.all(query, turnstile: @exemption)
end
