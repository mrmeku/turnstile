defmodule Turnstile.Cerbos.ClientTest do
  use ExUnit.Case, async: true

  alias Turnstile.Cerbos.Client
  alias Turnstile.Cerbos.Request
  alias Turnstile.Test

  @dead "127.0.0.1:1"
  @principal %{id: "an-account", roles: ["user"], attr: %{"clearance" => "cleared"}}
  @resource %{kind: "folder", id: "1", attr: %{"member_roles" => ["reader"]}}

  setup do
    :telemetry.attach(inspect(self()), Client.telemetry_event(), &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(inspect(self())) end)
    {:ok, address: Test.Cerbos.info().address}
  end

  test "a decision over resources answers the effect per action, with the policy it matched", ctx do
    assert {:ok, answered} = Client.check_resources(ctx.address, Request.logged(@principal, @resource, ["read"]))
    assert [result] = answered["results"]
    assert result["resource"] == %{"kind" => "folder", "id" => "1"}
    assert result["actions"]["read"] == "EFFECT_ALLOW"
    assert result["meta"]["actions"]["read"]["matchedPolicy"] =~ "folder"

    assert_receive {:request, %{duration: duration}, %{path: "/api/check/resources", outcome: :ok}}
    assert duration > 0
  end

  test "a query plan answers the filter over the attributes it could not resolve", ctx do
    body = %{
      requestId: "plan",
      includeMeta: true,
      principal: @principal,
      resource: %{kind: "folder"},
      action: "read"
    }

    assert {:ok, answered} = Client.plan_resources(ctx.address, body)
    assert answered["filter"]["kind"] == "KIND_CONDITIONAL"
    assert_receive {:request, _measurements, %{path: "/api/plan/resources", outcome: :ok}}
  end

  test "the server answers what it is and that it is serving", ctx do
    assert Client.serving?(ctx.address)
    assert {:ok, info} = Client.server_info(ctx.address)
    assert is_binary(info["version"])
    assert_receive {:request, _measurements, %{path: "/api/server_info", outcome: :ok}}
  end

  test "a body the server refuses is the status and what it said" do
    address = Test.Cerbos.info().address

    assert {:error, detail} = Client.check_resources(address, %{requestId: "empty"})
    assert detail =~ "cerbos answered 400"
    assert_receive {:request, _measurements, %{path: "/api/check/resources", outcome: :error}}
  end

  test "a sidecar out of reach is a failure rather than a wait" do
    refute Client.serving?(@dead)
    assert {:error, detail} = Client.plan_resources(@dead, %{requestId: "dead"})
    assert detail =~ "cerbos could not be reached"
    assert_receive {:request, _measurements, %{path: "/api/plan/resources", outcome: :error}}
  end

  @doc false
  @spec forward([atom()], map(), map(), pid()) :: :ok
  def forward(_event, measurements, metadata, pid) do
    send(pid, {:request, measurements, metadata})
    :ok
  end
end
