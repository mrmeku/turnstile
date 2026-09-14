defmodule Turnstile.Relay.LockTest do
  use ExUnit.Case, async: true

  alias Turnstile.Relay.Adapter.Lock
  alias Turnstile.Relay.TestSandbox
  alias Turnstile.TestRepos.Sandboxed

  setup tags do
    TestSandbox.setup(Sandboxed, tags)
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
