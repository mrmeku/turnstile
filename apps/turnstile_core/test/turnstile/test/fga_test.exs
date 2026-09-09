defmodule Turnstile.Test.FgaTest do
  use ExUnit.Case, async: true

  alias Turnstile.Test.Fga

  @moduletag :fga

  test "a server of the test's own answers its health endpoint" do
    server = Fga.start_supervised!()

    assert Fga.healthy?(server.address)
    assert server.address != server.grpc_address
    assert File.dir?(server.dir)
  end

  test "a server of the test's own takes the directory the caller names" do
    dir = Path.join([File.cwd!(), "tmp", "openfga-named-" <> Integer.to_string(System.unique_integer([:positive]))])
    on_exit(fn -> File.rm_rf!(dir) end)

    server = Fga.start_supervised!(dir: dir)

    assert server.dir == dir
    assert Fga.healthy?(server.address)
  end

  test "the options say what a caller may pass" do
    assert %NimbleOptions{} = Fga.options_schema()
    assert Fga.options_schema().schema[:timeout][:default] == 20_000

    assert_raise NimbleOptions.ValidationError, fn -> Fga.start_supervised!(datastore: "memory") end
  end

  test "an address nothing listens on is not healthy" do
    refute Fga.healthy?("127.0.0.1:1")
  end
end
