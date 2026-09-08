defmodule Turnstile.ConfigTest do
  use ExUnit.Case, async: false

  alias Turnstile.Adapter.Fake
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.Ledger.Memory

  defmodule NeedsLedger do
    @moduledoc false
    @behaviour Turnstile.Adapter

    @impl Turnstile.Adapter
    def requires_ledger, do: true
    @impl Turnstile.Adapter
    def scope_cap, do: 100
    @impl Turnstile.Adapter
    defdelegate authorize(subject, operation, object, environment, options), to: Fake
    @impl Turnstile.Adapter
    defdelegate check(subject, operation, object, environment, options), to: Fake
    @impl Turnstile.Adapter
    defdelegate batch(subject, operation, objects, environment, options), to: Fake
    @impl Turnstile.Adapter
    defdelegate scope(subject, operation, object_type, environment, options), to: Fake
  end

  setup do
    on_exit(fn -> :persistent_term.erase(Config) end)
  end

  test "new/1 validates the adapter tuple, its options, and the defaults" do
    assert {:ok, %Config{} = config} = Config.new(adapter: {Fake, verdict: :allow}, ledger: :none)
    assert config.adapter == {Fake, verdict: :allow}
    assert Config.adapter(config) == {Fake, verdict: :allow}
    assert config.ledger == :none
    assert config.ledger_counter == "default"
    assert config.clock == Turnstile.Clock.System
    assert config.caps == [batch_ids: 1_000, rule_bytes: 4_096, policy_content_bytes: 65_536]
  end

  test "new/1 accepts a bare adapter module and fills its option defaults" do
    assert {:ok, %Config{adapter: {Fake, verdict: :deny}} = config} = Config.new(adapter: Fake, ledger: :none)
    assert Config.adapter(config) == {Fake, verdict: :deny}
  end

  test "new/1 rejects a missing field, a wrong option, and a module that is not an adapter" do
    assert {:error, %Error.Invalid{what: :config}} = Config.new(ledger: :none)

    assert {:error, %Error.Invalid{what: :adapter, detail: detail}} =
             Config.new(adapter: {Fake, verdict: :maybe}, ledger: :none)

    assert detail =~ "verdict"
    assert {:error, %Error.Invalid{what: :adapter}} = Config.new(adapter: Enum, ledger: :none)
    assert {:error, %Error.Invalid{what: :adapter}} = Config.new(adapter: Turnstile.NoSuchAdapter, ledger: :none)
  end

  test "new/1 rejects options for an adapter that declares no schema" do
    assert {:ok, %Config{adapter: {NeedsLedger, []}}} =
             Config.new(adapter: NeedsLedger, ledger: {Memory, agent: self()})

    assert {:error, %Error.Invalid{what: :adapter, detail: detail}} =
             Config.new(adapter: {NeedsLedger, x: 1}, ledger: {Memory, agent: self()})

    assert detail =~ "takes no options"
  end

  test "new/1 validates the ledger tuple through the ledger's schema" do
    assert {:ok, %Config{ledger: {Memory, agent: pid}}} = Config.new(adapter: Fake, ledger: {Memory, agent: self()})
    assert pid == self()
    assert {:error, %Error.Invalid{what: :ledger}} = Config.new(adapter: Fake, ledger: {Memory, []})
    assert {:error, %Error.Invalid{what: :ledger}} = Config.new(adapter: Fake, ledger: {Enum, []})
    assert {:error, %Error.Invalid{what: :config}} = Config.new(adapter: Fake, ledger: :maybe)
  end

  test "new/1 refuses ledger mode none for an adapter that requires a ledger" do
    assert {:error, %Error.Unsupported{adapter: NeedsLedger, feature: :ledger_mode_none}} =
             Config.new(adapter: NeedsLedger, ledger: :none)
  end

  test "new!/1 raises the error" do
    assert_raise Error.Invalid, ~r/invalid config/, fn -> Config.new!([]) end
    assert %Config{} = Config.new!(adapter: Fake, ledger: :none)
  end

  test "resolve/0 fails when nothing is booted and nothing is overridden" do
    assert {:error, %Error.Invalid{what: :config, detail: "nothing booted and no override"}} = Config.resolve()
  end

  test "resolve/0 answers from the override alone" do
    Turnstile.Test.with_config(adapter: Fake, ledger: :none)
    assert {:ok, %Config{adapter: {Fake, verdict: :deny}}} = Config.resolve()
  end

  test "resolve/0 merges the override onto the boot struct and round-trips through to_keyword/1" do
    booted = Config.boot!(adapter: Fake, ledger: :none, ledger_counter: "boot")
    assert Config.new!(Config.to_keyword(booted)) == booted
    assert {:ok, ^booted} = Config.resolve()

    Turnstile.Test.with_config([ledger_counter: "override"], fn ->
      assert {:ok, %Config{ledger_counter: "override"}} = Config.resolve()
    end)

    assert {:ok, ^booted} = Config.resolve()
  end

  test "resolve/0 reads the override from the $callers chain" do
    Turnstile.Test.with_config(adapter: {Fake, verdict: :allow}, ledger: :none)

    assert {:ok, %Config{adapter: {Fake, verdict: :allow}}} =
             Task.await(Task.async(fn -> Task.await(Task.async(&Config.resolve/0)) end))

    assert {:error, %Error.Invalid{}} = Task.await(Task.async(fn -> Process.delete(:"$callers") && Config.resolve() end))
  end

  test "with_config/2 restores the previous override even when the function raises" do
    Turnstile.Test.with_config(adapter: Fake, ledger: :none)

    assert_raise RuntimeError, fn ->
      Turnstile.Test.with_config([ledger_counter: "inner"], fn -> raise "boom" end)
    end

    assert {:ok, %Config{ledger_counter: "default"}} = Config.resolve()
  end

  test "override_key/0 names the process dictionary key" do
    assert Config.override_key() == Config
  end
end
