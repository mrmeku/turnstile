defmodule ExampleRbac.ApplicationTest do
  # Not async: the application restarts here, after every async test has run.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Example.Audit.Store
  alias ExampleRbac.Policy
  alias Turnstile.Code.Binding
  alias Turnstile.Config

  test "the application boots again after a stop: the config, the binding, the supervisor, and the version" do
    {:ok, before} = Config.resolve()
    _stopped = capture_log(fn -> :ok = Application.stop(:example_rbac) end)
    refute Process.whereis(ExampleRbac.Supervisor)
    refute Process.whereis(Store)

    _started = capture_log(fn -> assert {:ok, [:example_rbac]} = Application.ensure_all_started(:example_rbac) end)
    assert Process.alive?(Process.whereis(ExampleRbac.Supervisor))
    assert Process.alive?(Process.whereis(Store))

    assert {:ok, %Config{} = config} = Config.resolve()
    assert config.ledger == before.ledger
    assert Config.adapter(config) == {Turnstile.Code, []}
    assert {:ok, %Binding{policy: Policy, repo: Example.Repo}} = Binding.resolve()
  end
end
