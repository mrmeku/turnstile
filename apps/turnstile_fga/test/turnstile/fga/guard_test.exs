defmodule Turnstile.Fga.GuardTest.Cleared do
  @moduledoc "A guard that admits what the environment says is cleared and nothing else."

  @behaviour Turnstile.Fga.Guard

  @impl Turnstile.Fga.Guard
  def admits?(operation, environment) when operation in [:read, :edit] do
    Map.get(environment, :cleared) == true
  end

  def admits?(_operation, _environment), do: false
end

defmodule Turnstile.Fga.GuardTest do
  # What every callback relies on when it consults a guard: it answers a
  # boolean about every operation under every environment, the same answer
  # twice, and admits nothing it was not told to admit, because a guard that
  # cannot tell is a guard that does not admit.
  use ExUnit.Case, async: true

  alias Turnstile.Fga.GuardTest.Cleared

  @now ~U[2026-09-09 12:00:00.000000Z]
  @admitted %{now: @now, cleared: true}
  @refused %{now: @now, cleared: false}
  @undeclared :turnstile_fga_guard_test_undeclared_operation

  @operations [:read, :edit]
  @environments [%{}, @admitted, @refused]

  test "every operation under every environment answers a boolean" do
    answers =
      for operation <- [@undeclared | @operations], environment <- @environments, do: ask(operation, environment)

    assert answers != []
    assert Enum.all?(answers, &is_boolean/1)
  end

  test "a guard asked twice about the same call answers the same" do
    for operation <- [@undeclared | @operations], environment <- @environments do
      assert ask(operation, environment) == ask(operation, environment)
    end
  end

  test "an environment the application says is admitted admits every operation" do
    for operation <- @operations,
        do: assert(ask(operation, @admitted), "#{inspect(operation)} under #{inspect(@admitted)}")
  end

  test "an environment the application says is refused refuses every operation" do
    for operation <- @operations, do: refute(ask(operation, @refused), "#{inspect(operation)} under #{inspect(@refused)}")
  end

  test "an operation the application never declared is not admitted, whatever the environment" do
    for environment <- @environments, do: refute(ask(@undeclared, environment))
  end

  defp ask(operation, environment), do: Cleared.admits?(operation, environment)
end
