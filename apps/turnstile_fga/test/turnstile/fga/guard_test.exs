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
  use Turnstile.Fga.GuardCase,
    async: true,
    guard: Turnstile.Fga.GuardTest.Cleared,
    operations: [:read, :edit],
    admitting: [%{now: ~U[2026-09-09 12:00:00.000000Z], cleared: true}],
    refusing: [%{now: ~U[2026-09-09 12:00:00.000000Z], cleared: false}]
end
