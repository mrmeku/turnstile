defmodule Turnstile.SchemaTest do
  use ExUnit.Case, async: true

  alias Turnstile.Schema.Fact
  alias Turnstile.Schema.Relationship

  defmodule Declared do
    @moduledoc false
    use Turnstile.Schema

    object_type :thing
    carries [:parts, :notes]
    fact(:owner_id, kind: :subject_attribute, subject: :owner_id)
    fact(:labels, kind: :object_attribute, object: :id, element: :label)
    relationship(subject: :user_id, object: :thing_id, attributes: [:role])
  end

  defmodule Empty do
    @moduledoc false
    use Turnstile.Schema
  end

  test "a schema records its declarations in order" do
    assert Declared.__turnstile__(:object_type) == :thing
    assert Declared.__turnstile__(:carries) == [:parts, :notes]

    assert Declared.__turnstile__(:facts) == [
             %Fact{column: :owner_id, kind: :subject_attribute, subject: :owner_id, object: nil, element: nil},
             %Fact{column: :labels, kind: :object_attribute, subject: nil, object: :id, element: :label}
           ]

    assert Declared.__turnstile__(:relationship) == %Relationship{
             subject: :user_id,
             object: :thing_id,
             attributes: [:role]
           }
  end

  test "a schema without declarations answers nil and empty" do
    assert Empty.__turnstile__(:object_type) == nil
    assert Empty.__turnstile__(:carries) == []
    assert Empty.__turnstile__(:facts) == []
    assert Empty.__turnstile__(:relationship) == nil
  end

  test "a second object_type, carries, or relationship raises" do
    assert_raise ArgumentError, ~r/already declares object_type/, fn ->
      defmodule TwoTypes do
        @moduledoc false
        use Turnstile.Schema

        object_type :a
        object_type :b
      end
    end

    assert_raise ArgumentError, ~r/already carries \[:a\]/, fn ->
      defmodule TwoCarries do
        @moduledoc false
        use Turnstile.Schema

        carries [:a]
        carries [:b, :a]
      end
    end

    assert_raise ArgumentError, ~r/already declares a relationship/, fn ->
      defmodule TwoRelationships do
        @moduledoc false
        use Turnstile.Schema

        relationship(subject: :a, object: :b)
        relationship(subject: :c, object: :d)
      end
    end
  end

  test "a fact with an unknown kind or a relationship without an object is refused" do
    assert_raise NimbleOptions.ValidationError, fn ->
      defmodule BadKind do
        @moduledoc false
        use Turnstile.Schema

        fact(:x, kind: :other)
      end
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      defmodule BadRelationship do
        @moduledoc false
        use Turnstile.Schema

        relationship(subject: :a)
      end
    end
  end
end
