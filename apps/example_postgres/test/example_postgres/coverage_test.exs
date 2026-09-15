defmodule ExamplePostgres.CoverageTest do
  @moduledoc """
  Declared-fact coverage (`docs/conformance.md` §2, `au12-07`) over the
  CUI policies: every column the policies of this binding read is a
  declared fact of the example.

  The policies are read back from the database the application booted
  against, column by column as the catalog records each dependency, and
  each column is set against the declarations of the schema it belongs
  to. A column no declaration covers fails the case with the column's
  name, because a decision that depended on it would rest on a fact no
  record of a change covers.
  """

  use ExUnit.Case, async: true

  alias Turnstile.Dev.Sandbox
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Coverage

  setup tags do
    Sandbox.setup(Example.Infrastructure.Repo, tags)
  end

  test "every column the policies read is a declared fact" do
    assert {:ok, %Binding{} = binding} = Binding.resolve()
    assert Coverage.check(binding) == :ok, "the policies read #{inspect(Coverage.undeclared(binding))}"
  end
end
