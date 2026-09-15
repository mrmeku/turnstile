defmodule ExampleRbac.ApplicationTest do
  # Not async: the application restarts here, after every async test has run.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Example.Infrastructure.Siem
  alias ExampleRbac.Infrastructure.Policy
  alias Turnstile.Config
  alias Turnstile.Rbac.Binding

  test "the application boots again after a stop: the config, the binding, the supervisor, and the version" do
    _stopped = capture_log(fn -> :ok = Application.stop(:example_rbac) end)
    refute Process.whereis(ExampleRbac.Supervisor)
    refute Process.whereis(Siem)

    _started = capture_log(fn -> assert {:ok, [:example_rbac]} = Application.ensure_all_started(:example_rbac) end)
    assert Process.alive?(Process.whereis(ExampleRbac.Supervisor))
    assert Process.alive?(Process.whereis(Siem))

    assert {:ok, %Config{} = config} = Config.resolve()
    assert Config.adapter(config) == {Turnstile.Rbac, []}
    assert {:ok, %Binding{policy: Policy, repo: Example.Infrastructure.Repo}} = Binding.resolve()
  end
end
