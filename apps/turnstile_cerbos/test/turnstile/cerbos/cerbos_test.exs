defmodule Turnstile.CerbosTest do
  use ExUnit.Case, async: true

  alias Turnstile.Answer
  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Conformance.Attributes
  alias Turnstile.Cerbos.Sidecar
  alias Turnstile.Cerbos.Version
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Fixture.Folder
  alias Turnstile.Object
  alias Turnstile.Subject
  alias Turnstile.Test
  alias Turnstile.TestRepos.Sandboxed

  @ann %Subject{id: "ann", kind: :user}
  @folder %Object{type: :folder, id: 1}

  @window ~s|
apiVersion: api.cerbos.dev/v1
resourcePolicy:
  version: default
  resource: folder
  rules:
    - actions: ["read"]
      effect: EFFECT_ALLOW
      roles: ["user"]
      condition:
        match:
          all:
            of:
              - expr: request.principal.attr.environment.reauthenticated_at != null
              - expr: >
                  timestamp(request.principal.attr.environment.now) -
                  timestamp(request.principal.attr.environment.reauthenticated_at) < duration("900s")
|

  defmodule Window do
    @moduledoc false
    use Turnstile.Cerbos.Attributes

    alias Turnstile.Fixture.Account

    principal :user, schema: Account do
    end

    resource :folder, schema: Folder do
    end

    environment do
      fact(:reauthenticated_at)
    end
  end

  setup do
    sidecar = Test.Cerbos.info()

    :ok =
      Binding.override(repo: Sandboxed, attributes: Attributes, policies: sidecar.policies, commit: "conformance")

    {:ok, address: sidecar.address, environment: %Environment{now: DateTime.utc_now()}}
  end

  test "the adapter needs no ledger, caps no scope, and its entry carries the address alone" do
    assert Turnstile.Cerbos.requires_ledger() == false
    assert Turnstile.Cerbos.scope_cap() == :none
    assert Turnstile.Cerbos.options_schema().schema[:address][:required]
    assert Keyword.keys(Turnstile.Cerbos.options_schema().schema) == [:address]
  end

  test "an entry with no address is an engine error naming the callback that failed", ctx do
    for {operation, call} <- callbacks(ctx, []) do
      assert {:error, %Error.Engine{} = error} = call.()
      assert error.adapter == Turnstile.Cerbos
      assert error.operation == operation
      assert error.detail == "the configuration entry names no address for the sidecar"
    end
  end

  test "a binding that does not resolve is an engine error naming the callback that failed", ctx do
    :ok = Binding.override(attributes: Folder)

    for {operation, call} <- callbacks(ctx, address: ctx.address) do
      assert {:error, %Error.Engine{operation: ^operation} = error} = call.()
      assert error.detail == "Turnstile.Fixture.Folder did not use Turnstile.Cerbos.Attributes"
    end
  end

  test "a policy that reads a request-time fact is answered from the moment the request carries" do
    sidecar = Sidecar.replayed!(Version.to_text([{"folder.yaml", @window}]))
    :ok = Binding.override(repo: Sandboxed, attributes: Window, policies: sidecar.policies, commit: "window")
    now = ~U[2026-09-09 12:00:00Z]
    options = [address: sidecar.address]

    fresh = %Environment{now: now, facts: %{reauthenticated_at: DateTime.shift(now, minute: -1)}}
    assert {:ok, %Answer{verdict: :allow}} = Turnstile.Cerbos.check(@ann, :read, @folder, fresh, options)

    stale = %Environment{now: now, facts: %{reauthenticated_at: DateTime.shift(now, second: -901)}}
    assert {:ok, %Answer{verdict: :deny}} = Turnstile.Cerbos.check(@ann, :read, @folder, stale, options)

    absent = %Environment{now: now}
    assert {:ok, %Answer{verdict: :deny}} = Turnstile.Cerbos.check(@ann, :read, @folder, absent, options)
  end

  # A decision for one row is one explanation with the answer taken out of
  # it, so a failure of `authorize` and of `check` names the explanation.
  defp callbacks(ctx, options) do
    [
      {:explain, fn -> Turnstile.Cerbos.authorize(@ann, :read, @folder, ctx.environment, options) end},
      {:explain, fn -> Turnstile.Cerbos.check(@ann, :read, @folder, ctx.environment, options) end},
      {:explain, fn -> Turnstile.Cerbos.explain(@ann, :read, @folder, ctx.environment, options) end},
      {:batch, fn -> Turnstile.Cerbos.batch(@ann, :read, [@folder], ctx.environment, options) end},
      {:scope, fn -> Turnstile.Cerbos.scope(@ann, :read, :folder, ctx.environment, options) end}
    ]
  end
end
