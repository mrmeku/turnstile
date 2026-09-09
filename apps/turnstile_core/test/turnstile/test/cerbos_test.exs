defmodule Turnstile.Test.CerbosTest do
  use ExUnit.Case, async: true

  alias Turnstile.Test.Cerbos

  @moduletag :cerbos

  setup do
    dir = Path.join([File.cwd!(), "tmp", "cerbos-policies-" <> Integer.to_string(System.unique_integer([:positive]))])
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{policies: dir}
  end

  test "a sidecar of the test's own answers its health endpoint", %{policies: policies} do
    sidecar = Cerbos.start_supervised!(policies: policies)

    assert Cerbos.healthy?(sidecar.address)
    assert sidecar.policies == policies
    assert File.exists?(sidecar.audit_log) or File.dir?(sidecar.dir)
    assert File.read!(sidecar.config_file) =~ ~s(httpListenAddr: "#{sidecar.address}")
    assert File.read!(sidecar.config_file) =~ "watchForChanges: true"
  end

  test "the options say what a caller may pass" do
    assert %NimbleOptions{} = Cerbos.options_schema()
    assert Cerbos.options_schema().schema[:policies][:required]

    assert_raise NimbleOptions.ValidationError, fn -> Cerbos.start_supervised!(watch: false) end
  end

  test "an address nothing listens on is not healthy" do
    refute Cerbos.healthy?("127.0.0.1:1")
  end
end
