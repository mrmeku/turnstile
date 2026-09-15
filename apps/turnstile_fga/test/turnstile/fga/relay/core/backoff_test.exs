defmodule Turnstile.Fga.Relay.Core.BackoffTest do
  use ExUnit.Case, async: true

  alias Turnstile.Fga.Relay.Core.Backoff
  alias Turnstile.Fga.Relay.Pass

  @options [idle: 1_000, backoff: 100, backoff_max: 1_000]

  test "a full batch means the next pass runs at once" do
    assert Backoff.wait({:ok, pass(more?: true)}, 0, @options) == 0
  end

  test "a batch that was not full waits the idle interval" do
    assert Backoff.wait({:ok, pass(more?: false)}, 0, @options) == 1_000
  end

  test "a failure waits the backoff, doubled once for each failure before it" do
    assert Backoff.wait({:error, :down}, 0, @options) == 100
    assert Backoff.wait({:error, :down}, 1, @options) == 200
    assert Backoff.wait({:error, :down}, 2, @options) == 400
  end

  test "a wait that would grow past the longest stops there, however long the outage" do
    assert Backoff.wait({:error, :down}, 10, @options) == 1_000
    assert Backoff.wait({:error, :down}, 1_000, @options) == 1_000
  end

  test "one pass that worked puts the count of failures back to zero" do
    assert Backoff.failures({:ok, pass(more?: false)}, 7) == 0
    assert Backoff.failures({:error, :down}, 7) == 8
  end

  defp pass(fields) do
    struct!(
      %Pass{name: :counting, held?: true, delivered: 0, position: 0, more?: false, at: DateTime.utc_now()},
      fields
    )
  end
end
