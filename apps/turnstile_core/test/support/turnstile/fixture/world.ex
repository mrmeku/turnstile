defmodule Turnstile.Fixture.World do
  @moduledoc """
  A population of the neutral fixture and the rule it obeys, for the
  conformance properties: accounts with or without clearance, folders,
  items in folders, and memberships of accounts on folders with a role.
  The rule, which every adapter's conformance artifact for the fixture
  encodes: `:read` on a folder needs any membership on it, `:edit` needs
  an editor membership, an item answers as its folder does, and an account
  without clearance is denied everything.

  Every write goes through the seam under a declared exemption, so a ledger
  configured for the test records the population as fact events, and the
  fold of those events is the state `facts/1` computes from the world.
  """

  import Ecto.Query, only: [order_by: 2]

  alias Ecto.Changeset
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Object

  @exemption {:exempt, "conformance fixture"}
  @operations [:read, :edit]
  @cleared "cleared"

  defstruct accounts: %{}, folders: [], items: %{}, memberships: %{}

  @typedoc "Account id to clearance; folder ids; item id to its folder; `{account, folder}` to role."
  @type t :: %__MODULE__{
          accounts: %{String.t() => String.t() | nil},
          folders: [pos_integer()],
          items: %{pos_integer() => pos_integer()},
          memberships: %{{String.t(), pos_integer()} => :reader | :editor}
        }

  @doc "The two operations the rule knows."
  @spec operations() :: [atom()]
  def operations, do: @operations

  @doc "The clearance value that permits."
  @spec cleared() :: String.t()
  def cleared, do: @cleared

  @doc "The exemption every fixture write declares."
  @spec exemption() :: {:exempt, String.t()}
  def exemption, do: @exemption

  @doc "The account ids."
  @spec subjects(t()) :: [String.t()]
  def subjects(%__MODULE__{accounts: accounts}) do
    accounts
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "Every folder and item as an object."
  @spec objects(t()) :: [Object.t()]
  def objects(%__MODULE__{folders: folders, items: items}) do
    item_ids = Enum.sort(Map.keys(items))
    Enum.map(folders, &%Object{type: :folder, id: &1}) ++ Enum.map(item_ids, &%Object{type: :item, id: &1})
  end

  @doc "The rule: what the world says about one subject, operation, and object."
  @spec allowed?(t(), String.t(), atom(), Object.t()) :: boolean()
  def allowed?(%__MODULE__{} = world, account, operation, %Object{type: :item, id: id}) do
    case Map.fetch(world.items, id) do
      {:ok, folder} -> allowed?(world, account, operation, %Object{type: :folder, id: folder})
      :error -> false
    end
  end

  def allowed?(%__MODULE__{} = world, account, operation, %Object{type: :folder, id: id}) do
    cleared? = Map.get(world.accounts, account) == @cleared
    role = Map.get(world.memberships, {account, id})
    cleared? and role_allows?(role, operation)
  end

  def allowed?(%__MODULE__{}, _account, _operation, %Object{}), do: false

  @doc "The subject, operation, object triples the rule allows."
  @spec grants(t()) :: [{String.t(), atom(), Object.ref()}]
  def grants(%__MODULE__{} = world) do
    for account <- subjects(world),
        operation <- @operations,
        object <- objects(world),
        allowed?(world, account, operation, object),
        do: {account, operation, Object.ref(object)}
  end

  @doc "The fold a ledger of this world's writes reaches: memberships and clearances by their fact keys."
  @spec facts(t()) :: %{Turnstile.Ledger.Fold.key() => term()}
  def facts(%__MODULE__{} = world) do
    memberships =
      Map.new(world.memberships, fn {{account, folder}, role} -> {{{:user, account}, {:folder, folder}, nil}, role} end)

    clearances =
      for {account, clearance} <- world.accounts, not is_nil(clearance), into: %{} do
        {{{:user, account}, nil, :clearance}, clearance}
      end

    Map.merge(memberships, clearances)
  end

  @doc "Write the world through the seam, accounts and folders first."
  @spec insert(module(), t()) :: :ok
  def insert(repo, %__MODULE__{} = world) when is_atom(repo) do
    world
    |> rows()
    |> Enum.each(&repo.insert!(&1, turnstile: @exemption))
  end

  @doc "Delete every fixture row through the seam, fact rows one at a time so the ledger records their erasure."
  @spec clear(module()) :: :ok
  def clear(repo) when is_atom(repo) do
    Enum.each(repo.all(Membership, turnstile: @exemption), &repo.delete!(&1, turnstile: @exemption))
    Enum.each(repo.all(Account, turnstile: @exemption), &repo.delete!(&1, turnstile: @exemption))
    {_count, nil} = repo.delete_all(Item, turnstile: @exemption)
    {_count, nil} = repo.delete_all(Folder, turnstile: @exemption)
    :ok
  end

  @doc "The world the tables hold."
  @spec read(module()) :: t()
  def read(repo) when is_atom(repo) do
    read = &repo.all(&1, turnstile: @exemption)
    folders = read.(order_by(Folder, :id))

    %__MODULE__{
      accounts: Map.new(read.(Account), &{&1.id, &1.clearance}),
      folders: Enum.map(folders, & &1.id),
      items: Map.new(read.(Item), &{&1.id, &1.folder_id}),
      memberships: Map.new(read.(Membership), &membership_of/1)
    }
  end

  @doc "Give the account a role on the folder, inserting or changing the membership, and return the world."
  @spec grant(module(), t(), String.t(), pos_integer(), :reader | :editor) :: t()
  def grant(repo, %__MODULE__{} = world, account, folder, role) when is_atom(repo) do
    case repo.get_by(Membership, [account_id: account, folder_id: folder], turnstile: @exemption) do
      nil ->
        repo.insert!(%Membership{account_id: account, folder_id: folder, role: role}, turnstile: @exemption)

      %Membership{} = membership ->
        repo.update!(Changeset.change(membership, role: role), turnstile: @exemption)
    end

    %{world | memberships: Map.put(world.memberships, {account, folder}, role)}
  end

  @doc "Remove the account's membership on the folder, if any, and return the world."
  @spec revoke(module(), t(), String.t(), pos_integer()) :: t()
  def revoke(repo, %__MODULE__{} = world, account, folder) when is_atom(repo) do
    case repo.get_by(Membership, [account_id: account, folder_id: folder], turnstile: @exemption) do
      nil -> :ok
      %Membership{} = membership -> repo.delete!(membership, turnstile: @exemption)
    end

    %{world | memberships: Map.delete(world.memberships, {account, folder})}
  end

  @doc "Set the account's clearance and return the world."
  @spec set_clearance(module(), t(), String.t(), String.t() | nil) :: t()
  def set_clearance(repo, %__MODULE__{} = world, account, clearance) when is_atom(repo) do
    account_row = repo.get!(Account, account, turnstile: @exemption)
    repo.update!(Changeset.change(account_row, clearance: clearance), turnstile: @exemption)
    %{world | accounts: Map.put(world.accounts, account, clearance)}
  end

  defp role_allows?(nil, _operation), do: false
  defp role_allows?(_role, :read), do: true
  defp role_allows?(:editor, :edit), do: true
  defp role_allows?(_role, _operation), do: false

  defp rows(%__MODULE__{} = world) do
    Enum.concat([accounts(world), folders(world), items(world), memberships(world)])
  end

  defp accounts(world), do: Enum.map(world.accounts, fn {id, clearance} -> %Account{id: id, clearance: clearance} end)
  defp folders(world), do: Enum.map(world.folders, &%Folder{id: &1, name: "folder #{&1}"})

  defp items(world),
    do: Enum.map(world.items, fn {id, folder} -> %Item{id: id, title: "item #{id}", folder_id: folder} end)

  defp membership_of(%Membership{} = membership) do
    {{membership.account_id, membership.folder_id}, membership.role}
  end

  defp memberships(world) do
    Enum.map(world.memberships, fn {{account, folder}, role} ->
      %Membership{account_id: account, folder_id: folder, role: role}
    end)
  end
end
