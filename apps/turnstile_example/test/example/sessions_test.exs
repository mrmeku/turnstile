defmodule Example.SessionsTest do
  use ExUnit.Case, async: true

  alias Example.Sessions
  alias Turnstile.Environment

  @now ~U[2026-09-08 12:00:00Z]

  test "a session is fresh within the window of the clock and stale outside it" do
    assert Sessions.window() == 900
    assert Sessions.fresh?(%Environment{now: @now, facts: %{reauthenticated_at: @now}})
    assert Sessions.fresh?(%Environment{now: @now, facts: %{reauthenticated_at: DateTime.shift(@now, minute: -15)}})
    refute Sessions.fresh?(%Environment{now: @now, facts: %{reauthenticated_at: DateTime.shift(@now, second: -901)}})
    refute Sessions.fresh?(%Environment{now: @now, facts: %{reauthenticated_at: DateTime.shift(@now, second: 1)}})
  end

  test "an absent or malformed fact is stale" do
    refute Sessions.fresh?(%Environment{now: @now, facts: %{}})
    refute Sessions.fresh?(%Environment{now: @now, facts: %{reauthenticated_at: "yesterday"}})
  end
end
