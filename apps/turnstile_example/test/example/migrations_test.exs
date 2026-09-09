defmodule Example.MigrationsTest do
  use ExUnit.Case, async: true

  alias Example.Migrations.Domain

  test "the options are validated" do
    assert_raise NimbleOptions.ValidationError, fn -> Domain.up(app_role: :not_a_string) end
  end

  test "the tables the helper creates are the schemas' sources" do
    sources =
      for module <- [
            Example.Agency,
            Example.Office,
            Example.Program,
            Example.Category,
            Example.User,
            Example.AccountRole,
            Example.Assignment,
            Example.OfficeRole,
            Example.Document,
            Example.Marking,
            Example.Portion,
            Example.Proposal,
            Example.OverrideReport
          ],
          do: module.__schema__(:source)

    assert Enum.sort(sources) == Enum.sort(Domain.tables())
  end
end
