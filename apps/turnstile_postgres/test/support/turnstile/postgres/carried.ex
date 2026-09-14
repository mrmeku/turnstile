defmodule Turnstile.Postgres.Carried do
  @moduledoc """
  Schemas for the two shapes of carried relation the fixture does not hold:
  one carried through another relation, which has a foreign key nowhere,
  and one whose key the carrying schema holds itself. What counts as
  declared is read from the declarations alone, so these need no tables and
  no policies.
  """

  use Boundary, top_level?: true, deps: [Ecto, Turnstile], exports: [Folder, Item, Shelf]
end

defmodule Turnstile.Postgres.Carried.Item do
  @moduledoc "A row a folder holds, whose folder no declaration carries."

  use Ecto.Schema
  use Turnstile.Schema

  @type t :: %__MODULE__{}

  schema "turnstile_carried_items" do
    belongs_to(:folder, Turnstile.Postgres.Carried.Folder)
  end

  object_type(:carried_item)
end

defmodule Turnstile.Postgres.Carried.Folder do
  @moduledoc "A folder that carries the shelf it belongs to, whose key it holds itself."

  use Ecto.Schema
  use Turnstile.Schema

  alias Turnstile.Postgres.Carried.Item
  alias Turnstile.Postgres.Carried.Shelf

  @type t :: %__MODULE__{}

  schema "turnstile_carried_folders" do
    belongs_to(:shelf, Shelf)
    has_many(:items, Item)
  end

  object_type(:carried_folder)
  carries([:shelf])
end

defmodule Turnstile.Postgres.Carried.Shelf do
  @moduledoc "A shelf that carries its folders and, through them, their items."

  use Ecto.Schema
  use Turnstile.Schema

  alias Turnstile.Postgres.Carried.Folder

  @type t :: %__MODULE__{}

  schema "turnstile_carried_shelves" do
    has_many(:folders, Folder)
    has_many(:shelf_items, through: [:folders, :items])
  end

  object_type(:carried_shelf)
  carries([:folders, :shelf_items])
end
