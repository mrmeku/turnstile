defmodule Turnstile.Repo.FactsTest.Team do
  @moduledoc false
  use Ecto.Schema
  use Turnstile.Schema

  @primary_key {:id, :string, autogenerate: false}

  schema "facts_test_teams" do
    field(:members, {:array, :string})
    field(:label, :string)
  end

  object_type(:team)
  fact(:members, kind: :relationship, object: :id, element: :user)
  fact(:label, kind: :object_attribute, object: :id)
end

defmodule Turnstile.Repo.FactsTest.Seat do
  @moduledoc false
  use Ecto.Schema
  use Turnstile.Schema

  schema "facts_test_seats" do
    field(:user_id, :string)
    belongs_to(:team, Turnstile.Repo.FactsTest.Team, type: :string)
  end

  relationship(subject: :user_id, object: :team_id)
end

defmodule Turnstile.Repo.FactsTest.Grant do
  @moduledoc false
  use Ecto.Schema
  use Turnstile.Schema

  schema "facts_test_grants" do
    field(:user_id, :string)
    field(:role, :string)
    field(:level, :integer)
    belongs_to(:team, Turnstile.Repo.FactsTest.Team, type: :string)
  end

  relationship(subject: :user_id, object: :team_id, attributes: [:role, :level])
end

defmodule Turnstile.Repo.FactsTest.Untyped do
  @moduledoc false
  use Ecto.Schema
  use Turnstile.Schema

  schema "facts_test_untyped" do
    field(:user_id, :string)
    field(:thing_id, :string)
    belongs_to(:other, Turnstile.Repo.FactsTest.Team, type: :string)
  end

  relationship(subject: :user_id, object: :thing_id)
end

defmodule Turnstile.Repo.FactsTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Id
  alias Turnstile.Repo.Facts
  alias Turnstile.Repo.FactsTest.Grant
  alias Turnstile.Repo.FactsTest.Seat
  alias Turnstile.Repo.FactsTest.Team
  alias Turnstile.Repo.FactsTest.Untyped
  alias Turnstile.Subject

  @stamp %{by: Subject.library(), operation_id: Id.new(), at: ~U[2026-09-08 00:00:00Z]}

  test "a set-valued fact yields one event per element added or removed, with the element as subject" do
    team = %Team{id: "t1", members: ["a", "b"], label: "blue"}

    assert [
             %FactEvent{kind: :relationship, subject_ref: {:user, "a"}, object_ref: {:team, "t1"}, old: nil, new: "a"},
             %FactEvent{kind: :relationship, subject_ref: {:user, "b"}, old: nil, new: "b"},
             %FactEvent{kind: :object_attribute, subject_ref: nil, object_ref: {:team, "t1"}, old: nil, new: "blue"}
           ] = Facts.events(Team, nil, team, @stamp)

    assert [%FactEvent{attribute: :members, subject_ref: {:user, "a"}, old: "a", new: nil}] =
             Facts.events(Team, team, %{team | members: ["b"]}, @stamp)

    assert [
             %FactEvent{attribute: :members, old: "a", new: nil},
             %FactEvent{attribute: :members, old: "b", new: nil},
             %FactEvent{attribute: :label, old: "blue", new: nil}
           ] = Facts.events(Team, team, nil, @stamp)
  end

  test "a relationship with no attributes records its existence as true" do
    seat = %Seat{user_id: "u1", team_id: "t1"}

    assert [%FactEvent{kind: :relationship, subject_ref: {:user, "u1"}, object_ref: {:team, "t1"}, old: nil, new: true}] =
             Facts.events(Seat, nil, seat, @stamp)

    assert [%FactEvent{attribute: nil, old: true, new: nil}] = Facts.events(Seat, seat, nil, @stamp)
  end

  test "a relationship with several attributes records them as a map, and a move is a removal and an addition" do
    grant = %Grant{user_id: "u1", team_id: "t1", role: "admin", level: 2}

    assert [%FactEvent{old: nil, new: %{role: "admin", level: 2}}] = Facts.events(Grant, nil, grant, @stamp)

    assert [%FactEvent{attribute: :role, old: "admin", new: "member"}] =
             Facts.events(Grant, grant, %{grant | role: "member"}, @stamp)

    assert [
             %FactEvent{object_ref: {:team, "t1"}, old: %{role: "admin", level: 2}, new: nil},
             %FactEvent{object_ref: {:team, "t2"}, old: nil, new: %{role: "admin", level: 2}}
           ] = Facts.events(Grant, grant, %{grant | team_id: "t2"}, @stamp)
  end

  test "an object column that names no object type is a mapping error" do
    error =
      assert_raise(Error.Invalid, fn ->
        Facts.events(Untyped, nil, %Untyped{user_id: "u1", thing_id: "x"}, @stamp)
      end)

    assert error.what == :fact_mapping
    assert Exception.message(error) =~ "Untyped.thing_id names no object type"
  end

  test "touched/2 keeps the fields a bulk write names that are fact columns" do
    assert Facts.touched(Grant, [:role, :inserted_at, :team_id]) == [:role, :team_id]
    assert Facts.touched(Team, [:label, :members, :name]) == [:label, :members]
    assert Facts.touched(Turnstile.Repo, [:anything]) == []
  end
end
