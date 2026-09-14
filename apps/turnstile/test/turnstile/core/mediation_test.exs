defmodule Turnstile.Core.MediationTest do
  use ExUnit.Case, async: true

  alias Turnstile.Core.Mediation
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Exemption
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Id
  alias Turnstile.Test.Fake

  test "the option's schema is a NimbleOptions schema that admits a resolved mediation" do
    assert %NimbleOptions{} = Mediation.schema()
    assert {:ok, %Mediation{}} = Mediation.validate_option(Mediation.empty({:all, 2}))
  end

  test "related/2 follows a through association and answers nil for an unknown one" do
    assert Mediation.related(Folder, :items) == Item
    assert Mediation.related(Folder, :item_folders) == Folder
    assert Mediation.related(Folder, :missing) == nil
  end

  test "carried_closure/1 is the root and every schema its carried associations reach" do
    assert Mediation.carried_closure(Folder) == [Folder, Item]
    assert Mediation.carried_closure(Item) == [Item]
  end

  test "a decision carries the root's associations, a denial raises, and an exemption records its caller" do
    decision = decision(:folder, 1)

    assert %Mediation{decision: ^decision, carried: [Folder, Item]} = Mediation.decided({:all, 2}, Folder, decision)
    assert %Mediation{carried: []} = Mediation.decided({:all, 2}, "turnstile_fixture_folders", decision)

    denial = %{decision | verdict: :deny, reason: :deny_by_default}
    assert_raise Error, fn -> Mediation.decided({:all, 2}, Folder, denial) end

    assert %Mediation{exemption: %Exemption{kind: :library, caller: __MODULE__, reason: "library"}} =
             Mediation.library({:all, 2}, Folder, __MODULE__)

    assert %Mediation{exemption: %Exemption{kind: :declared, caller: __MODULE__, reason: "a reason"}} =
             Mediation.declared({:all, 2}, Folder, __MODULE__, "a reason")
  end

  defp decision(type, id) do
    %Decision{
      id: Id.new(),
      subject: {:user, "user-1"},
      object: {type, id},
      operation: :read,
      verdict: :allow,
      reason: :allowed,
      adapter: Fake,
      policy_version: nil,
      operation_id: Id.new(),
      at: DateTime.utc_now()
    }
  end
end
