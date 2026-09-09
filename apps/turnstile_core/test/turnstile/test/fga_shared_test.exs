defmodule Turnstile.Test.FgaSharedTest do
  # Not async: the run's server is registered in `:persistent_term`, one term
  # for the virtual machine, and this module erases it for its own duration.
  use ExUnit.Case, async: false

  alias Turnstile.Test.Fga

  @moduletag :fga

  test "the run's server is started once and answered to every caller after" do
    previous = :persistent_term.get(Fga, nil)
    :persistent_term.erase(Fga)
    on_exit(fn -> if previous, do: :persistent_term.put(Fga, previous), else: :persistent_term.erase(Fga) end)

    assert_raise RuntimeError, ~r/no shared server/, fn -> Fga.info() end

    shared = Fga.start_shared()
    assert Fga.start_shared() == shared
    assert Fga.info() == shared
    assert Fga.healthy?(shared.address)

    assert :ok = Fga.stop(shared)
    assert :ok = Fga.stop_shared(:ok)
    refute File.dir?(shared.dir)
    refute Fga.healthy?(shared.address)
  end
end
