defmodule Turnstile.Fixture do
  @moduledoc """
  A neutral set of schemas for core's own seam tests: a folder that carries
  its items, an item that does not carry its folder back, a membership
  that is a relationship grant, and an account with one fact column. They
  name no domain of any application.

  The folder, item, and membership schemas share this file because their
  associations refer to one another, and the dependency gate forbids a
  cycle between files.
  """

  use Boundary, top_level?: true, deps: [Ecto, Turnstile], exports: [Account, Folder, Item, Membership, World]
end

defmodule Turnstile.Fixture.Item do
  @moduledoc "A protected object type inside a folder; it does not carry the folder back."

  use Ecto.Schema
  use Turnstile.Schema

  alias Turnstile.Fixture.Folder

  @type t :: %__MODULE__{}

  schema "turnstile_fixture_items" do
    field(:title, :string)
    belongs_to(:folder, Folder)
  end

  object_type(:item)
end

defmodule Turnstile.Fixture.Membership do
  @moduledoc "A relationship grant: an account holds a role on a folder. Unprotected as a query target."

  use Ecto.Schema
  use Turnstile.Schema

  alias Turnstile.Fixture.Folder

  @type t :: %__MODULE__{}

  schema "turnstile_fixture_memberships" do
    field(:account_id, :string)
    field(:role, Ecto.Enum, values: [:reader, :editor])
    belongs_to(:folder, Folder)
  end

  relationship(subject: :account_id, object: :folder_id, attributes: [:role])
end

defmodule Turnstile.Fixture.Folder do
  @moduledoc "A protected object type that carries its items."

  use Ecto.Schema
  use Turnstile.Schema

  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership

  @type t :: %__MODULE__{}

  schema "turnstile_fixture_folders" do
    field(:name, :string)
    has_many(:items, Item)
    has_many(:memberships, Membership)
    has_many(:item_folders, through: [:items, :folder])
  end

  object_type(:folder)
  carries([:items])
end
