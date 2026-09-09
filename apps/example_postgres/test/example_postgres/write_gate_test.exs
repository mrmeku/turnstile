defmodule ExamplePostgres.WriteGateTest do
  @moduledoc """
  The defense-in-depth property this binding has and no other: a marking
  change that C7 refuses is refused by the database, whether or not the
  application asked. The write goes through the owner-role repo as a
  statement, not through the port, so nothing of the seam is between it and
  the table.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Example.Fixture

  @update "UPDATE markings SET controls = ARRAY['federal_only'] WHERE document_id = $1"

  setup do
    :ok = Sandbox.checkout(Example.Repo, sandbox: false)
    :ok = Fixture.truncate!(Example.OwnerRepo)
    on_exit(fn -> Fixture.truncate!(Example.OwnerRepo) end)
    :ok
  end

  test "a C7-violating marking change is refused by the database whether or not the application asked" do
    world = Fixture.world!()
    document = Fixture.document!(world)

    error = assert_raise Postgrex.Error, fn -> Example.OwnerRepo.query!(@update, [document.id]) end

    assert error.postgres.code == :insufficient_privilege
    assert error.postgres.message =~ "row-level security policy"
  end
end
