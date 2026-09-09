defmodule Turnstile.Fga.ModelTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Fga.Model

  defp compiled(definition), do: Model.compile!("model\nschema 1.1\n\ntype folder\n  relations\n" <> definition)

  defp relation(definition, relation) do
    compiled(definition)["type_definitions"]
    |> List.first()
    |> get_in(["relations", relation])
  end

  defp restrictions(definition, relation) do
    compiled(definition)["type_definitions"]
    |> List.first()
    |> get_in(["metadata", "relations", relation, "directly_related_user_types"])
  end

  test "the conformance model compiles into the types, the relations, and the condition" do
    model = Model.read!("priv/conformance/model.fga")

    assert model["schema_version"] == "1.1"
    assert Enum.map(model["type_definitions"], & &1["type"]) == ["user", "clearance", "folder", "item"]
    assert Map.keys(model["conditions"]) == ["while_cleared"]

    assert model["conditions"]["while_cleared"] == %{
             "name" => "while_cleared",
             "expression" => ~s(clearance == "cleared"),
             "parameters" => %{"clearance" => %{"type_name" => "TYPE_NAME_STRING"}}
           }
  end

  test "a type with no relations is the type alone" do
    model = Model.read!("priv/conformance/model.fga")

    assert List.first(model["type_definitions"]) == %{"type" => "user"}
  end

  test "a relation reached through another is a tuple to userset over the relation that reaches it" do
    model = Model.read!("priv/conformance/model.fga")
    item = Enum.find(model["type_definitions"], &(&1["type"] == "item"))

    assert item["relations"]["can_read"] == %{
             "tupleToUserset" => %{
               "tupleset" => %{"relation" => "folder"},
               "computedUserset" => %{"relation" => "can_read"}
             }
           }
  end

  test "a direct list says this in the tree and names its types in the metadata" do
    assert relation("    define reader: [user]\n", "reader") == %{"this" => %{}}
    assert restrictions("    define reader: [user]\n", "reader") == [%{"type" => "user"}]
  end

  test "a direct list entry states a condition, every user of a type, and the holders of a relation" do
    definition = "    define reader: [user with while_cleared, user:*, group#member]\n"

    assert restrictions(definition, "reader") == [
             %{"type" => "user", "condition" => "while_cleared"},
             %{"type" => "user", "wildcard" => %{}},
             %{"type" => "group", "relation" => "member"}
           ]
  end

  test "every user of a type under a condition carries both" do
    definition = "    define reader: [user:* with while_cleared]\n"

    assert restrictions(definition, "reader") == [
             %{"type" => "user", "wildcard" => %{}, "condition" => "while_cleared"}
           ]
  end

  test "a relation on the same object is a computed userset" do
    assert relation("    define can_edit: editor\n", "can_edit") == %{"computedUserset" => %{"relation" => "editor"}}
    assert restrictions("    define can_edit: editor\n", "can_edit") == []
  end

  test "or is a union, and is an intersection, and but not is a difference" do
    assert relation("    define a: b or c\n", "a") == %{
             "union" => %{
               "child" => [%{"computedUserset" => %{"relation" => "b"}}, %{"computedUserset" => %{"relation" => "c"}}]
             }
           }

    assert relation("    define a: b and c\n", "a") == %{
             "intersection" => %{
               "child" => [%{"computedUserset" => %{"relation" => "b"}}, %{"computedUserset" => %{"relation" => "c"}}]
             }
           }

    assert relation("    define a: b but not c\n", "a") == %{
             "difference" => %{
               "base" => %{"computedUserset" => %{"relation" => "b"}},
               "subtract" => %{"computedUserset" => %{"relation" => "c"}}
             }
           }
  end

  test "a union of three is one union of three children" do
    assert %{"union" => %{"child" => [_first, _second, _third]}} = relation("    define a: b or c or d\n", "a")
  end

  test "parentheses say which operator binds first, and the direct list of a term inside them is kept" do
    definition = "    define a: (b but not c) or ([user] but not d)\n"

    assert %{"union" => %{"child" => [first, second]}} = relation(definition, "a")
    assert %{"difference" => %{"base" => %{"computedUserset" => %{"relation" => "b"}}}} = first
    assert %{"difference" => %{"base" => %{"this" => %{}}}} = second
    assert restrictions(definition, "a") == [%{"type" => "user"}]
  end

  test "a definition that mixes operators without parentheses is an error, not a guess" do
    assert {:error, %Error.Invalid{what: :model, detail: detail}} =
             Model.compile("model\nschema 1.1\n\ntype folder\n  relations\n    define a: b or c but not d\n")

    assert detail =~ "parentheses"
  end

  test "a model whose first lines are not the model and the schema is an error" do
    assert {:error, %Error.Invalid{detail: detail}} = Model.compile("type user\n")
    assert detail =~ "opens with a model line"
  end

  test "a schema this module does not compile is an error naming both versions" do
    assert {:error, %Error.Invalid{detail: detail}} = Model.compile("model\nschema 1.2\n")
    assert detail =~ "1.2"
    assert detail =~ Model.schema_version()
  end

  test "a line outside a type and a condition, a define with no colon, and a stray line are errors" do
    assert {:error, %Error.Invalid{detail: outside}} = Model.compile("model\nschema 1.1\nreader\n")
    assert outside =~ "outside a type"

    assert {:error, %Error.Invalid{detail: colon}} =
             Model.compile("model\nschema 1.1\ntype folder\n  relations\n    define reader\n")

    assert colon =~ "no definition after a colon"

    assert {:error, %Error.Invalid{detail: stray}} = Model.compile("model\nschema 1.1\ntype folder\n  reader: [user]\n")
    assert stray =~ "neither relations nor a define"
  end

  test "a direct list that is not closed is an error" do
    assert {:error, %Error.Invalid{detail: detail}} =
             Model.compile("model\nschema 1.1\ntype folder\n  relations\n    define reader: [user\n")

    assert detail =~ "not closed by"
  end

  test "a condition on one line and a condition over several read the same" do
    over_lines = "model\nschema 1.1\ncondition c(at: timestamp) {\n  at < now\n}\n"
    on_one = "model\nschema 1.1\ncondition c(at: timestamp) { at < now }\n"

    assert Model.compile!(over_lines) == Model.compile!(on_one)
    assert Model.compile!(on_one)["conditions"]["c"]["expression"] == "at < now"
    assert Model.compile!(on_one)["conditions"]["c"]["parameters"] == %{"at" => %{"type_name" => "TYPE_NAME_TIMESTAMP"}}
  end

  test "a condition with no parameters declares none" do
    assert Model.compile!("model\nschema 1.1\ncondition c() { true }\n")["conditions"]["c"]["parameters"] == %{}
  end

  test "a condition the regular shape does not fit, a parameter with no type, and an unknown type are errors" do
    assert {:error, %Error.Invalid{detail: shape}} = Model.compile("model\nschema 1.1\ncondition c at < now }\n")
    assert shape =~ "a condition is a name"

    assert {:error, %Error.Invalid{detail: untyped}} = Model.compile("model\nschema 1.1\ncondition c(at) { true }\n")
    assert untyped =~ "names no type after a colon"

    assert {:error, %Error.Invalid{detail: unknown}} =
             Model.compile("model\nschema 1.1\ncondition c(at: money) { true }\n")

    assert unknown =~ "not a parameter type"
  end

  test "the parameter types are the ones a condition may declare" do
    assert Model.parameter_types()["string"] == "TYPE_NAME_STRING"
    assert Model.parameter_types()["timestamp"] == "TYPE_NAME_TIMESTAMP"
  end

  test "a file that is not there is an error naming it" do
    assert {:error, %Error.Invalid{detail: detail}} = Model.read("priv/conformance/absent.fga")
    assert detail =~ "priv/conformance/absent.fga"
  end

  test "compiling text that does not read raises the error" do
    assert_raise Error.Invalid, fn -> Model.compile!("type user\n") end
    assert_raise Error.Invalid, fn -> Model.read!("priv/conformance/absent.fga") end
  end
end
