defmodule Turnstile.Code.CoverageTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2, from: 2, subquery: 1]

  alias Turnstile.Code.Conformance.Roles
  alias Turnstile.Code.Coverage
  alias Turnstile.Code.Policy
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership

  defmodule Reads do
    @moduledoc false
    @spec name(Turnstile.Subject.t(), Turnstile.Environment.t()) :: Ecto.Query.dynamic_expr()
    def name(_subject, _environment), do: dynamic([row], row.name == "public")

    @spec joined(Turnstile.Subject.t(), Turnstile.Environment.t()) :: Ecto.Query.dynamic_expr()
    def joined(%{id: id}, _environment) do
      dynamic([row], row.id in subquery(from(m in Membership, where: m.account_id == ^id, select: m.folder_id)))
    end

    @spec raw(Turnstile.Subject.t(), Turnstile.Environment.t()) :: Ecto.Query.dynamic_expr()
    def raw(_subject, _environment), do: dynamic([row], fragment("? = 'public'", row.name))

    @spec mapped(Turnstile.Subject.t(), Turnstile.Environment.t()) :: Ecto.Query.dynamic_expr()
    def mapped(%{id: id}, _environment) do
      members = from(m in Membership, where: m.account_id == ^id, select: %{folder: m.folder_id})
      dynamic([_row], exists(from(s in subquery(members), select: s.folder)))
    end

    @spec parent(Turnstile.Subject.t(), Turnstile.Environment.t()) :: Ecto.Query.dynamic_expr()
    def parent(_subject, _environment), do: dynamic([row], not is_nil(row.folder_id))

    @spec grandparent(Turnstile.Subject.t(), Turnstile.Environment.t()) :: Ecto.Query.dynamic_expr()
    def grandparent(_subject, _environment) do
      notes = from(n in Turnstile.Code.CoverageTest.Note, where: not is_nil(n.folder_id), select: n.id)
      dynamic([row], row.note_id in subquery(notes))
    end
  end

  defmodule Note do
    @moduledoc false
    use Ecto.Schema
    use Turnstile.Schema

    object_type(:note)
    carries([:folder])

    schema "turnstile_coverage_test_notes" do
      belongs_to(:folder, Folder)
    end
  end

  defmodule NamePolicy do
    @moduledoc false
    use Policy

    role :reader, [:read]

    object Folder do
      grant :membership, Membership
      predicate :named, &Reads.name/2
    end
  end

  defmodule SubqueryPolicy do
    @moduledoc false
    use Policy

    role :reader, [:read]

    object Folder do
      grant :membership, Membership
      predicate :joined, &Reads.joined/2
    end
  end

  defmodule MappedPolicy do
    @moduledoc false
    use Policy

    role :reader, [:read]

    object Folder do
      grant :membership, Membership
      predicate :mapped, &Reads.mapped/2
    end
  end

  defmodule Remark do
    @moduledoc false
    use Ecto.Schema
    use Turnstile.Schema

    object_type(:remark)
    carries([:note])

    schema "turnstile_coverage_test_remarks" do
      belongs_to(:note, Note)
    end
  end

  defmodule ClosurePolicy do
    @moduledoc false
    use Policy

    role :reader, [:read]

    object Remark do
      predicate :grandparent, &Reads.grandparent/2
    end
  end

  defmodule CarriedPolicy do
    @moduledoc false
    use Policy

    role :reader, [:read]

    object Note do
      predicate :parent, &Reads.parent/2
    end
  end

  defmodule FragmentPolicy do
    @moduledoc false
    use Policy

    role :reader, [:read]

    object Folder do
      predicate :raw, &Reads.raw/2
    end
  end

  test "every column the conformance rules read is a declared fact" do
    assert Coverage.check(Roles) == :ok
    assert Coverage.check!(Roles) == :ok
  end

  test "the coverage failure names the undeclared column and its schema" do
    assert Coverage.check(NamePolicy) == {:error, [{Folder, :name}]}

    assert_raise ArgumentError, ~r/name of Turnstile.Fixture.Folder/, fn -> Coverage.check!(NamePolicy) end
  end

  test "the walk follows subqueries, where every column the fixture reads is declared" do
    assert Coverage.check(SubqueryPolicy) == :ok
    reads = Coverage.reads(SubqueryPolicy)
    assert {Membership, :account_id} in reads
    assert {Membership, :folder_id} in reads
  end

  test "a fragment cannot be walked, so it is a finding" do
    assert Coverage.check(FragmentPolicy) == {:error, [{:fragment, "? = 'public'"}]}
    assert_raise ArgumentError, ~r/fragment "\? = 'public'"/, fn -> Coverage.check!(FragmentPolicy) end
  end

  test "a field of a subquery source counts as declared, since the subquery's reads are walked" do
    assert Coverage.check(MappedPolicy) == :ok
    assert {Membership, :folder_id} in Coverage.reads(MappedPolicy)
  end

  test "the foreign key of a carried belongs_to is declared on the schema that holds it" do
    assert Coverage.check(CarriedPolicy) == :ok
  end

  test "the closure of carried relations counts: a carried schema's own carried key is declared" do
    assert Coverage.check(ClosurePolicy) == :ok
    assert {Note, :folder_id} in Coverage.reads(ClosurePolicy)
  end
end
