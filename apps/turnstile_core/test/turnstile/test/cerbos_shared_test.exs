defmodule Turnstile.Test.CerbosSharedTest do
  # Not async: the run's sidecar is registered in `:persistent_term`, one term
  # for the virtual machine, and this module erases it for its own duration.
  use ExUnit.Case, async: false

  alias Turnstile.Test.Cerbos

  @moduletag :cerbos

  setup do
    dir = Path.join([File.cwd!(), "tmp", "cerbos-policies-" <> Integer.to_string(System.unique_integer([:positive]))])
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{policies: dir}
  end

  test "the run's sidecar is started once and answered to every caller after", %{policies: policies} do
    previous = :persistent_term.get(Cerbos, nil)
    :persistent_term.erase(Cerbos)
    on_exit(fn -> if previous, do: :persistent_term.put(Cerbos, previous), else: :persistent_term.erase(Cerbos) end)

    assert_raise RuntimeError, ~r/no shared sidecar/, fn -> Cerbos.info() end

    shared = Cerbos.start_shared(policies: policies)
    assert Cerbos.start_shared(policies: policies) == shared
    assert Cerbos.info() == shared
    assert Cerbos.healthy?(shared.address)

    assert :ok = Cerbos.stop(shared)
    assert :ok = Cerbos.stop_shared(:ok)
    refute File.dir?(shared.dir)
    refute Cerbos.healthy?(shared.address)
  end
end
