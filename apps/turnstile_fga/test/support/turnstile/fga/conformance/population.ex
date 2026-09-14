defmodule Turnstile.Fga.Conformance.Population do
  @moduledoc """
  A population of the neutral fixture for the case templates: three accounts,
  two of them cleared, three folders, and four memberships across them. It is
  written and taken away a row at a time through the seam, so every change it
  makes is one the handler sees.

  A folder with no membership on it and an account with no clearance are both
  in here on purpose, since an object that requires no tuple is what the
  templates hold the mapping to as much as one that does. The disturbance is
  one membership taken away, which leaves the folder it sat on in the tables
  for a drain to put right.
  """

  @behaviour Turnstile.Fga.Population

  alias Turnstile.Fga.Population
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership

  @accounts [{"acct-a", "cleared"}, {"acct-b", "cleared"}, {"acct-c", nil}]
  @exemption {:exempt, "fga population"}
  @folders [1, 2, 3]
  @memberships [{"acct-a", 1, :editor}, {"acct-b", 1, :reader}, {"acct-a", 2, :reader}, {"acct-c", 2, :editor}]

  @impl Population
  def write(repo) do
    Enum.each(@accounts, fn {id, clearance} -> insert(repo, %Account{id: id, clearance: clearance}) end)
    Enum.each(@folders, fn id -> insert(repo, %Folder{id: id, name: "folder #{id}"}) end)

    Enum.each(@memberships, fn {account, folder, role} ->
      insert(repo, %Membership{account_id: account, folder_id: folder, role: role})
    end)
  end

  @impl Population
  def clear(repo) do
    Enum.each(repo.all(Membership, turnstile: @exemption), &repo.delete!(&1, turnstile: @exemption))
    Enum.each(repo.all(Account, turnstile: @exemption), &repo.delete!(&1, turnstile: @exemption))
    Enum.each(repo.all(Folder, turnstile: @exemption), &repo.delete!(&1, turnstile: @exemption))
  end

  @impl Population
  def disturb(repo) do
    membership = repo.get_by!(Membership, [account_id: "acct-b", folder_id: 1], turnstile: @exemption)
    _deleted = repo.delete!(membership, turnstile: @exemption)

    :ok
  end

  @impl Population
  def absent("clearance"), do: "clearance:nothing-is-classified-this-way"
  def absent("folder"), do: "folder:999999"
  def absent(type), do: "#{type}:999999"

  defp insert(repo, row) do
    _inserted = repo.insert!(row, turnstile: @exemption)

    :ok
  end
end
