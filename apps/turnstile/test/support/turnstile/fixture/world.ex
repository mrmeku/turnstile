defmodule Turnstile.Fixture.World do
  @moduledoc """
  A population of the neutral fixture and the rule it obeys, this
  repository's `Turnstile.Conformance.World`: accounts with or without
  clearance, folders, items in folders, and memberships of accounts on
  folders, each with a role, the kind of subject that holds it, and an
  expiry. The rule, which every adapter's conformance artifact for the
  fixture encodes: `:read` on a folder needs a live membership on it held
  by the asking kind, `:edit` needs such a membership with the editor role,
  an item answers as its folder does, and an account without clearance is
  denied everything. A membership is live when it names no expiry or one
  after the moment the configured clock reads, which is where `allowed?/4`
  reads it from.

  Every write goes through the seam under a declared exemption, so the
  population reaches the tables the way an application's own writes do.
  """

  @behaviour Turnstile.Conformance.World

  use ExUnitProperties

  alias Turnstile.Config
  alias Turnstile.Conformance.World
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership

  @accounts ~w(acct-a acct-b acct-c)
  @exemption {:exempt, "conformance fixture"}
  @operations [:read, :edit]
  @roles [:reader, :editor]
  @kinds [:user, :non_person_entity, :privileged]
  @expiries [nil, ~U[2025-01-01 00:00:00Z], ~U[2999-01-01 00:00:00Z]]
  @cleared "cleared"
  @focus_id "acct-a"
  @focus {:user, @focus_id}

  defstruct accounts: %{}, folders: [], items: %{}, memberships: %{}

  @typedoc "What a membership holds: the role, the kind of subject it is held by, and when it expires."
  @type membership :: %{role: :reader | :editor, kind: Turnstile.subject_kind(), expires_at: DateTime.t() | nil}

  @typedoc "Account id to clearance; folder ids; item id to its folder; `{account, folder}` to its membership."
  @type t :: %__MODULE__{
          accounts: %{String.t() => String.t() | nil},
          folders: [pos_integer()],
          items: %{pos_integer() => pos_integer()},
          memberships: %{{String.t(), pos_integer()} => membership()}
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
      grants = list_of(tuple({member_of(Map.keys(accounts)), integer(1..folder_count), membership()}), max_length: 4)
      map(tuple({items, grants}), &build(accounts, folder_count, &1))
    end)
  end

  @doc "One cleared account, one folder, one unexpiring editor membership on it held by a user."
  @impl World
  @spec granted() :: t()
  def granted do
    %__MODULE__{accounts: %{@focus_id => @cleared}, folders: [1], memberships: %{{@focus_id, 1} => held(:editor)}}
  end

  @doc "An unexpiring membership of the role, held by a user."
  @spec held(:reader | :editor) :: membership()
  def held(role) when role in [:reader, :editor], do: %{role: role, kind: :user, expires_at: nil}

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

  @doc "The accounts as users, and the focus account as a privileged subject too."
  @impl World
  @spec subjects(t()) :: [Turnstile.subject()]
  def subjects(%__MODULE__{accounts: accounts}) do
    users =
      accounts
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(&{:user, &1})

    if Map.has_key?(accounts, @focus_id), do: Enum.concat(users, [{:privileged, @focus_id}]), else: users
  end

  @doc "Every folder and item as an object."
  @impl World
  @spec objects(t()) :: [Turnstile.object()]
  def objects(%__MODULE__{folders: folders, items: items}) do
    item_ids = Enum.sort(Map.keys(items))
    Enum.map(folders, &{:folder, &1}) ++ Enum.map(item_ids, &{:item, &1})
  end

  @doc "The rule: what the world says about one subject, operation, and object, at the configured clock's moment."
  @impl World
  @spec allowed?(t(), Turnstile.subject(), atom(), Turnstile.object()) :: boolean()
  def allowed?(%__MODULE__{} = world, {_kind, _account} = subject, operation, {:item, id}) do
    case Map.fetch(world.items, id) do
      {:ok, folder} -> allowed?(world, subject, operation, {:folder, folder})
      :error -> false
    end
  end

  def allowed?(%__MODULE__{} = world, {kind, account}, operation, {:folder, id}) do
    cleared? = Map.get(world.accounts, account) == @cleared
    cleared? and holds?(Map.get(world.memberships, {account, id}), kind, operation, now())
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

  @doc """
  Insert one membership through the seam and nothing else: the role, held
  by the subject's kind, with the attributes given, of which `expires_at` is
  the one the rule reads. The world it leaves is returned.
  """
  @impl World
  @spec insert_grant(module(), t(), Turnstile.subject(), pos_integer(), keyword()) :: t()
  def insert_grant(repo, %__MODULE__{} = world, {kind, account}, folder, attributes)
      when is_atom(repo) and is_list(attributes) do
    expires_at = Keyword.get(attributes, :expires_at)
    role = Keyword.get(attributes, :role, :editor)
    row = %Membership{account_id: account, folder_id: folder, role: role, subject_kind: kind, expires_at: expires_at}
    _inserted = repo.insert!(row, turnstile: @exemption)

    held = %{role: role, kind: kind, expires_at: expires_at}
    %{world | memberships: Map.put(world.memberships, {account, folder}, held)}
  end

  @doc "Take the subject's clearance away through the seam, which changes the account fact the rule reads."
  @impl World
  @spec disqualify(module(), t(), Turnstile.subject()) :: t()
  def disqualify(repo, %__MODULE__{} = world, {_kind, account}) when is_atom(repo) do
    changeset = Ecto.Changeset.change(repo.get!(Account, account, turnstile: @exemption), clearance: nil)
    _updated = repo.update!(changeset, turnstile: @exemption)

    %{world | accounts: Map.put(world.accounts, account, nil)}
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

  defp membership do
    kind = frequency([{4, constant(:user)}, {1, member_of(@kinds)}])
    expiry = frequency([{2, constant(nil)}, {1, member_of(@expiries)}])
    map(tuple({member_of(@roles), kind, expiry}), fn {role, kind, at} -> %{role: role, kind: kind, expires_at: at} end)
  end

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

    memberships = Map.new(grants, fn {account, folder, held} -> {{account, folder}, held} end)
    %__MODULE__{accounts: accounts, folders: Enum.to_list(1..folder_count), items: items, memberships: memberships}
  end

  defp holds?(nil, _kind, _operation, _now), do: false

  defp holds?(%{role: role, kind: held_by, expires_at: expires_at}, kind, operation, now) do
    held_by == kind and live?(expires_at, now) and role_allows?(role, operation)
  end

  defp live?(nil, _now), do: true
  defp live?(%DateTime{} = expires_at, now), do: DateTime.after?(expires_at, now)

  defp role_allows?(_role, :read), do: true
  defp role_allows?(:editor, :edit), do: true
  defp role_allows?(_role, _operation), do: false

  defp now do
    {:ok, %Config{clock: clock}} = Config.resolve()
    clock.()
  end

  defp rows(%__MODULE__{} = world) do
    Enum.concat([accounts(world), folders(world), items(world), memberships(world)])
  end

  defp accounts(world), do: Enum.map(world.accounts, fn {id, clearance} -> %Account{id: id, clearance: clearance} end)
  defp folders(world), do: Enum.map(world.folders, &%Folder{id: &1, name: "folder #{&1}"})

  defp items(world),
    do: Enum.map(world.items, fn {id, folder} -> %Item{id: id, title: "item #{id}", folder_id: folder} end)

  defp memberships(world) do
    Enum.map(world.memberships, fn {{account, folder}, %{role: role, kind: kind, expires_at: expires_at}} ->
      %Membership{account_id: account, folder_id: folder, role: role, subject_kind: kind, expires_at: expires_at}
    end)
  end
end
