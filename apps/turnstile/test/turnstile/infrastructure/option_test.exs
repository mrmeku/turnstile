defmodule Turnstile.Infrastructure.OptionTest do
  use ExUnit.Case, async: true

  alias Turnstile.Decision
  alias Turnstile.Domain.Mediation
  alias Turnstile.Fixture.Folder
  alias Turnstile.Id
  alias Turnstile.Infrastructure.Option
  alias Turnstile.Test.Fake
  alias Turnstile.TestRepos.Sandboxed

  test "a decision on a table name carries nothing, and a resolved mediation is passed through" do
    decision = decision(:folder, 1)

    assert {%Mediation{carried: [], decision: ^decision}, opts} =
             Option.resolve(Sandboxed, {:all, 2}, "turnstile_fixture_folders", turnstile: decision)

    assert {%Mediation{call: {:one, 2}} = nested, nested_opts} = Option.resolve(Sandboxed, {:one, 2}, Folder, opts)
    assert nested_opts[:turnstile] == nested
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
