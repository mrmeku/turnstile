defmodule Turnstile.Repo.MediationTest do
  use ExUnit.Case, async: true

  alias Turnstile.Adapter.Fake
  alias Turnstile.Decision
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Id
  alias Turnstile.Reason
  alias Turnstile.Repo.Mediation
  alias Turnstile.Subject
  alias Turnstile.TestRepos.Sandboxed

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

  test "a decision on a table name carries nothing, and a resolved mediation is passed through" do
    decision = decision(:folder, 1)

    assert {%Mediation{carried: [], decision: ^decision}, opts} =
             Mediation.resolve(Sandboxed, {:all, 2}, "turnstile_fixture_folders", turnstile: decision)

    assert {%Mediation{call: {:one, 2}} = nested, nested_opts} = Mediation.resolve(Sandboxed, {:one, 2}, Folder, opts)
    assert nested_opts[:turnstile] == nested
  end

  defp decision(type, id) do
    %Decision{
      id: Id.new(),
      subject: %Subject{id: "user-1", kind: :user},
      object: {type, id},
      operation: :read,
      verdict: :allow,
      reason: %Reason{code: :allowed, message: "allowed by the fake adapter"},
      adapter: Fake,
      policy_version: nil,
      head_position: nil,
      applied_position: nil,
      operation_id: Id.new(),
      at: DateTime.utc_now()
    }
  end
end
