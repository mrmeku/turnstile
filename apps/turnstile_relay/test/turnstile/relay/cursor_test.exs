defmodule Turnstile.Relay.CursorTest do
  use ExUnit.Case, async: true

  alias Turnstile.Relay.Cursor
  alias Turnstile.Relay.TestSandbox
  alias Turnstile.TestRepos.Sandboxed

  setup tags do
    TestSandbox.setup(Sandboxed, tags)
  end

  test "a runner no row names stands at zero, which is below every position" do
    assert Cursor.position(Sandboxed, :never_ran) == 0
  end

  test "a position recorded is the position read back, and recording again replaces it" do
    assert Cursor.advance(Sandboxed, :advancing, 7) == :ok
    assert Cursor.position(Sandboxed, :advancing) == 7

    assert Cursor.advance(Sandboxed, :advancing, 19) == :ok
    assert Cursor.position(Sandboxed, :advancing) == 19
  end

  test "two runners keep their own positions" do
    :ok = Cursor.advance(Sandboxed, :one, 3)
    :ok = Cursor.advance(Sandboxed, :other, 11)

    assert Cursor.position(Sandboxed, :one) == 3
    assert Cursor.position(Sandboxed, :other) == 11
  end
end
