defmodule Example.MigrationsTest do
  use ExUnit.Case, async: true

  alias Example.Migrations.Domain

  test "the options are validated" do
    assert_raise NimbleOptions.ValidationError, fn -> Domain.up(app_role: :not_a_string) end
  end

  test "the tables the helper creates are the schemas' sources" do
    sources = for module <- Example.schemas(), do: module.__schema__(:source)

    assert Enum.sort(sources) == Enum.sort(Domain.tables())
  end
end
