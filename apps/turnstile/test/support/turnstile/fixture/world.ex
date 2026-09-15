defmodule Turnstile.Fixture.World do
  @moduledoc """
  A population of the neutral fixture and the rule it obeys, this
  repository's `Turnstile.Conformance.World`: accounts with or without
  clearance, folders, items in folders, and memberships of accounts on
  folders with a role. The rule, which every adapter's conformance
  artifact for the fixture encodes: `:read` on a folder needs any
  membership on it, `:edit` needs an editor membership, an item answers as
  its folder does, and an account without clearance is denied everything.

  Every write goes through the seam under a declared exemption, so the
  population reaches the tables the way an application's own writes do.
  """

  @behaviour Turnstile.Conformance.World

  use ExUnitProperties

  alias Turnstile.Conformance.World
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership

  @accounts ~w(acct-a acct-b acct-c)
  @exemption {:exempt, "conformance fixture"}
  @operations [:read, :edit]
  @roles [:reader, :editor]
  @cleared "cleared"
  @focus_id "acct-a"
  @focus {:user, @focus_id}

  defstruct accounts: %{}, folders: [], items: %{}, memberships: %{}

  @typedoc "Account id to clearance; folder ids; item id to its folder; `{account, folder}` to role."
  @type t :: %__MODULE__{
          accounts: %{String.t() => String.t() | nil},
          folders: [pos_integer()],
          items: %{pos_integer() => pos_integer()},
          memberships: %{{String.t(), pos_integer()} => :reader | :editor}
        }

  @doc "The two protected schemas the properties scope over."
  @impl World
  @spec schemas() :: [module()]
  def schemas, do: [Folder, Item]

  @doc "The schema the shape cases fill and scope over."
  @impl World
  @spec scope_schema() :: module()
  def scope_schema, do: Folder

  @doc "The two operations the rule knows."
  @impl World
  @spec operations() :: [atom()]
  def operations, do: @operations

  @doc "The roles a membership carries."
  @impl World
  @spec grant_types() :: [atom()]
  def grant_types, do: @roles

  @doc "The clearance value that permits."
  @spec cleared() :: String.t()
  def cleared, do: @cleared

  @doc "The exemption every fixture write declares."
  @impl World
  @spec exemption() :: {:exempt, String.t()}
  def exemption, do: @exemption

  @doc "The folder a membership on it covers."
  @impl World
  @spec object_of(pos_integer()) :: Turnstile.object()
  def object_of(folder) when is_integer(folder), do: {:folder, folder}

  @doc "A world: one to three accounts, one to three folders, up to four items and memberships."
  @impl World
  @spec generator() :: StreamData.t(t())
  def generator do
    bind(population(), fn {accounts, folder_count} ->
      items = list_of(integer(1..folder_count), max_length: 4)
      grants = list_of(tuple({member_of(Map.keys(accounts)), integer(1..folder_count), role()}), max_length: 4)
      map(tuple({items, grants}), &build(accounts, folder_count, &1))
    end)
  end

  @doc "One cleared account, one folder, one editor membership on it."
  @impl World
  @spec granted() :: t()
  def granted do
    %__MODULE__{accounts: %{@focus_id => @cleared}, folders: [1], memberships: %{{@focus_id, 1} => :editor}}
  end

  @doc "`granted/0` with the membership taken out."
  @impl World
  @spec ungranted() :: t()
  def ungranted, do: %{granted() | memberships: %{}}

  @doc "`granted/0` with three folders, only the first of them granted."
  @impl World
  @spec scoped() :: t()
  def scoped, do: %{granted() | folders: [1, 2, 3]}

  @doc "The account the fixed worlds grant to, and the folder they grant it on."
  @impl World
  @spec focus(t()) :: {Turnstile.subject(), pos_integer()}
  def focus(%__MODULE__{}), do: {@focus, 1}

  @doc "The accounts, as subjects."
  @impl World
  @spec subjects(t()) :: [Turnstile.subject()]
  def subjects(%__MODULE__{accounts: accounts}) do
    accounts
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(&{:user, &1})
  end

  @doc "Every folder and item as an object."
  @impl World
  @spec objects(t()) :: [Turnstile.object()]
  def objects(%__MODULE__{folders: folders, items: items}) do
    item_ids = Enum.sort(Map.keys(items))
    Enum.map(folders, &{:folder, &1}) ++ Enum.map(item_ids, &{:item, &1})
  end

  @doc "The rule: what the world says about one subject, operation, and object."
  @impl World
  @spec allowed?(t(), Turnstile.subject(), atom(), Turnstile.object()) :: boolean()
  def allowed?(%__MODULE__{} = world, {_kind, _account} = subject, operation, {:item, id}) do
    case Map.fetch(world.items, id) do
      {:ok, folder} -> allowed?(world, subject, operation, {:folder, folder})
      :error -> false
    end
  end

  def allowed?(%__MODULE__{} = world, {_kind, account}, operation, {:folder, id}) do
    cleared? = Map.get(world.accounts, account) == @cleared
    role = Map.get(world.memberships, {account, id})
    role_allows?(role, operation) and cleared?
  end

  def allowed?(%__MODULE__{}, {_kind, _account}, _operation, {_type, _id}), do: false

  @doc "The subject, operation, object triples the rule allows."
  @spec grants(t()) :: [{Turnstile.subject(), atom(), Turnstile.object()}]
  def grants(%__MODULE__{} = world) do
    for subject <- subjects(world),
        operation <- @operations,
        object <- objects(world),
        allowed?(world, subject, operation, object),
        do: {subject, operation, object}
  end

  @doc "Write the world through the seam, accounts and folders first."
  @impl World
  @spec insert(module(), t()) :: :ok
  def insert(repo, %__MODULE__{} = world) when is_atom(repo) do
    world
    |> rows()
    |> Enum.each(&repo.insert!(&1, turnstile: @exemption))
  end

  @doc "Delete every fixture row through the seam, fact rows one at a time so the seam records each erasure."
  @impl World
  @spec clear(module()) :: :ok
  def clear(repo) when is_atom(repo) do
    Enum.each(repo.all(Membership, turnstile: @exemption), &repo.delete!(&1, turnstile: @exemption))
    Enum.each(repo.all(Account, turnstile: @exemption), &repo.delete!(&1, turnstile: @exemption))
    {_count, nil} = repo.delete_all(Item, turnstile: @exemption)
    {_count, nil} = repo.delete_all(Folder, turnstile: @exemption)
    :ok
  end

  @doc "Remove the account's membership on the folder, if any, and return the world."
  @impl World
  @spec revoke(module(), t(), Turnstile.subject(), pos_integer()) :: t()
  def revoke(repo, %__MODULE__{} = world, {_kind, account}, folder) when is_atom(repo) do
    case repo.get_by(Membership, [account_id: account, folder_id: folder], turnstile: @exemption) do
      nil -> :ok
      %Membership{} = membership -> repo.delete!(membership, turnstile: @exemption)
    end

    %{world | memberships: Map.delete(world.memberships, {account, folder})}
  end

  @doc "Insert one membership through the seam and nothing else."
  @impl World
  @spec insert_grant(module(), Turnstile.subject(), pos_integer(), :reader | :editor) :: :ok
  def insert_grant(repo, {_kind, account}, folder, role) when is_atom(repo) do
    repo.insert!(%Membership{account_id: account, folder_id: folder, role: role}, turnstile: @exemption)
    :ok
  end

  @doc "Bring the folder table up to that many rows, the added ones granted to nobody."
  @impl World
  @spec fill(module(), t(), pos_integer()) :: :ok
  def fill(repo, %__MODULE__{} = world, count) when is_atom(repo) and is_integer(count) do
    held = MapSet.new(world.folders)
    rows = for id <- 1..count, not MapSet.member?(held, id), do: %{id: id, name: "folder #{id}"}
    {_written, nil} = repo.insert_all(Folder, rows, turnstile: @exemption)
    :ok
  end

  defp role, do: member_of(@roles)

  defp clearance, do: frequency([{3, constant(@cleared)}, {1, constant(nil)}])

  defp population do
    accounts = list_of(tuple({member_of(@accounts), clearance()}), min_length: 1, max_length: 3)
    tuple({map(accounts, &Map.new/1), integer(1..3)})
  end

  defp build(accounts, folder_count, {item_folders, grants}) do
    items =
      item_folders
      |> Enum.with_index(1)
      |> Map.new(fn {folder, item} -> {item, folder} end)

    memberships = Map.new(grants, fn {account, folder, role} -> {{account, folder}, role} end)
    %__MODULE__{accounts: accounts, folders: Enum.to_list(1..folder_count), items: items, memberships: memberships}
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

  defp memberships(world) do
    Enum.map(world.memberships, fn {{account, folder}, role} ->
      %Membership{account_id: account, folder_id: folder, role: role}
    end)
  end
end
