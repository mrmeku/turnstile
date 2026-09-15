defmodule Turnstile.Fga.Relay.LockTest do
  use ExUnit.Case, async: true

  alias Turnstile.Dev.Sandbox
  alias Turnstile.Fga.Relay.Infrastructure.Lock
  alias Turnstile.TestRepos.Sandboxed

  setup tags do
    Sandbox.setup(Sandboxed, tags)
  end

  test "a pass with nobody else about takes the lock" do
    assert Sandboxed.transaction(fn -> Lock.taken?(Sandboxed, :uncontended) end) == {:ok, true}
  end

  test "the same connection asking twice is told yes both times" do
    assert Sandboxed.transaction(fn ->
             assert Lock.taken?(Sandboxed, :twice)
             Lock.taken?(Sandboxed, :twice)
           end) == {:ok, true}
  end
end
