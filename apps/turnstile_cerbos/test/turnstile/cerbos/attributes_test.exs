defmodule Turnstile.Cerbos.AttributesTest do
  use ExUnit.Case, async: true

  alias Turnstile.Cerbos.Attribute
  alias Turnstile.Cerbos.Attributes
  alias Turnstile.Cerbos.Conformance.Memberships
  alias Turnstile.Error
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder

  defmodule Declarations do
    @moduledoc false
    use Attributes

    principal :user, schema: Account do
      attribute :clearance, column: :clearance
    end

    resource :folder, schema: Folder do
      attribute :name, column: :name
      attribute :member_roles, subquery: &Memberships.folder_roles_for/1
    end

    environment do
      fact(:reauthenticated_at)
    end
  end

  test "the declarations name the kinds, the side each is on, and the schema behind it" do
    assert Attributes.kinds(Declarations) == [{:principal, :user, Account}, {:resource, :folder, Folder}]
    assert Attributes.principals(Declarations) == [:user]
    assert Attributes.resources(Declarations) == [:folder]
    assert Attributes.declared?(Declarations, :user)
    assert Attributes.declared?(Declarations, :folder)
    refute Attributes.declared?(Declarations, :nothing)
    assert Attributes.schema_of(Declarations, :folder) == Folder
    assert Attributes.schema_of(Declarations, :nothing) == nil
  end

  test "the attributes of a kind come back in the order they were written" do
    assert [%Attribute{name: :clearance, source: {:column, :clearance}}] = Attributes.attributes_of(Declarations, :user)

    assert [%Attribute{name: :name}, %Attribute{name: :member_roles}] =
             Attributes.attributes_of(Declarations, :folder)

    assert Attributes.attributes_of(Declarations, :nothing) == []

    assert Enum.map(Attributes.all(Declarations), &elem(&1, 0)) == [:user, :folder, :folder]
  end

  test "the request-time facts the declarations name come back in the order they were written" do
    assert Attributes.facts(Declarations) == [:reauthenticated_at]
  end

  test "the name the request-time facts travel under is not a name a declaration may take" do
    assert Attribute.reserved() == :environment

    assert {:error, %Error.Invalid{what: :attribute} = error} = Attribute.new(:environment, column: :environment)
    assert error.detail == "attribute environment is the name the request-time facts travel under"
  end

  test "an environment block declares a fact and refuses anything else" do
    declaration =
      quote do
        defmodule Nothing do
          @moduledoc false
          use Turnstile.Cerbos.Attributes

          environment do
            reauthenticated_at()
          end
        end
      end

    assert_raise ArgumentError, ~r/declares a fact with `fact :name`/, fn -> Code.eval_quoted(declaration) end
  end

  test "one declaration is found by its kind and its name" do
    assert %Attribute{source: {:subquery, fun}} = Attributes.find(Declarations, :folder, :member_roles)
    assert fun == (&Memberships.folder_roles_for/1)
    assert Attributes.find(Declarations, :folder, :nothing) == nil
  end

  test "a module that did not use the declarations does not declare" do
    assert Attributes.declares?(Declarations)
    refute Attributes.declares?(Folder)
    refute Attributes.declares?(Turnstile.Cerbos.AttributesTest.NotAModuleAtAll)
    assert Attributes.kind_options_schema().schema[:schema][:required]
  end

  test "an attribute names a column or a subquery, and neither or both is an error" do
    assert {:ok, %Attribute{source: {:column, :clearance}} = column} = Attribute.new(:clearance, column: :clearance)
    assert Attribute.column?(column)

    assert {:ok, %Attribute{} = subquery} = Attribute.new(:roles, subquery: &Memberships.folder_roles_for/1)
    refute Attribute.column?(subquery)

    assert {:error, %Error.Invalid{what: :attribute} = neither} = Attribute.new(:nothing, [])
    assert neither.detail == "attribute nothing names neither a column nor a subquery"

    both = [column: :clearance, subquery: &Memberships.folder_roles_for/1]
    assert {:error, %Error.Invalid{} = error} = Attribute.new(:both, both)
    assert error.detail == "attribute both names both a column and a subquery"
  end

  test "an option the schema does not accept is an error naming the attribute" do
    assert {:error, %Error.Invalid{what: :attribute} = error} = Attribute.new(:clearance, column: "clearance")
    assert error.detail =~ "attribute clearance invalid value for :column option"
    assert Attribute.options_schema().schema[:column][:type] == :atom

    assert_raise Error.Invalid, fn -> Attribute.new!(:clearance, column: "clearance") end
    assert %Attribute{} = Attribute.new!(:clearance, column: :clearance)
  end
end
