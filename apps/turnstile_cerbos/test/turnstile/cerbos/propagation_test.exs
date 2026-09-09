defmodule Turnstile.Cerbos.PropagationTest do
  use ExUnit.Case, async: true

  alias Turnstile.Cerbos.Client
  alias Turnstile.Cerbos.Propagation
  alias Turnstile.Cerbos.Request
  alias Turnstile.Cerbos.Sidecar
  alias Turnstile.Test

  @principal %{id: "an-account", roles: ["user"], attr: %{"clearance" => "cleared"}}
  @resource %{kind: "folder", id: "1", attr: %{"member_roles" => ["reader"]}}

  # The same folder policy with the rule for reading taken out of it, which
  # is a change the sidecar answers differently once it has read it.
  @tightened ~S"""
  apiVersion: api.cerbos.dev/v1
  resourcePolicy:
    version: default
    resource: folder
    rules:
      - actions: ["edit"]
        effect: EFFECT_ALLOW
        roles: ["user", "non_person_entity", "privileged"]
        condition:
          match:
            expr: request.principal.attr.clearance == "cleared"
  """

  test "a policy written into the directory reaches the sidecar, and the interval is the measurement" do
    sidecar = Sidecar.own!()
    assert reads?(sidecar.address)

    {published, measurement} =
      Propagation.measure(
        fn -> Propagation.swap!(sidecar.policies, [{"folder.yaml", @tightened}]) end,
        fn -> not reads?(sidecar.address) end
      )

    assert [{"folder.yaml", previous}] = published
    assert previous =~ ~s(actions: ["read"])
    assert %Propagation{} = measurement
    assert measurement.total == measurement.publish + measurement.poll
    assert measurement.floor == Test.poll_interval()
    assert measurement.poll >= 0

    assert Propagation.to_keyword(measurement) == [
             total: measurement.total,
             publish: measurement.publish,
             poll: measurement.poll,
             floor: measurement.floor
           ]

    :ok = Propagation.restore!(sidecar.policies, published)
    assert Test.poll(fn -> reads?(sidecar.address) end, 30_000)
  end

  test "what a swap came back with is what the directory held, and putting it back is what was there" do
    directory = Path.join([File.cwd!(), "tmp", "propagation-#{System.unique_integer([:positive])}"])
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    File.write!(Path.join(directory, "held.yaml"), "before\n")

    previous = Propagation.swap!(directory, [{"held.yaml", "after\n"}, {"nested/new.yaml", "new\n"}])

    assert previous == [{"held.yaml", "before\n"}, {"nested/new.yaml", nil}]
    assert File.read!(Path.join(directory, "held.yaml")) == "after\n"
    assert File.read!(Path.join(directory, "nested/new.yaml")) == "new\n"

    assert Propagation.restore!(directory, previous) == :ok
    assert File.read!(Path.join(directory, "held.yaml")) == "before\n"
    refute File.exists?(Path.join(directory, "nested/new.yaml"))
  end

  test "the options a measurement takes name the deadline it polls to" do
    assert Propagation.options_schema().schema[:timeout][:default] == 30_000
  end

  defp reads?(address) do
    body = Request.logged(@principal, @resource, ["read"])

    case Client.check_resources(address, body) do
      {:ok, %{"results" => [result | _rest]}} -> result["actions"]["read"] == "EFFECT_ALLOW"
      _other -> false
    end
  end
end
