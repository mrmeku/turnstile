defmodule Turnstile.ConfigTest do
  use ExUnit.Case, async: false

  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.Test.Fake

  defmodule NoOptions do
    @moduledoc false
    @behaviour Turnstile.Adapter

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

  # The umbrella root starts every application before any suite runs, so a
  # boot config may exist; these tests assume none and put it back after.
  setup do
    booted = :persistent_term.get(Config, nil)
    :persistent_term.erase(Config)
    on_exit(fn -> if booted, do: :persistent_term.put(Config, booted), else: :persistent_term.erase(Config) end)
  end

  test "new/1 validates the adapter tuple, its options, and the defaults" do
    assert {:ok, %Config{} = config} = Config.new(adapter: {Fake, verdict: :allow})
    assert config.adapter == {Fake, verdict: :allow}
    assert Config.adapter(config) == {Fake, verdict: :allow}
    assert %DateTime{time_zone: "Etc/UTC"} = config.clock.()
    assert config.caps == [policy_content_bytes: 65_536]
  end

  test "new/1 accepts a bare adapter module and fills its option defaults" do
    assert {:ok, %Config{adapter: {Fake, verdict: :deny}} = config} = Config.new(adapter: Fake)
    assert Config.adapter(config) == {Fake, verdict: :deny}
    assert Config.adapter(%{config | adapter: Fake}) == {Fake, []}
  end

  test "new/1 rejects a missing field, a wrong option, and a module that is not an adapter" do
    assert {:error, %Error{reason: :invalid, detail: "invalid config: " <> _rest}} =
             Config.new(clock: &DateTime.utc_now/0)

    assert {:error, %Error{reason: :invalid, detail: "invalid adapter: " <> detail}} =
             Config.new(adapter: {Fake, verdict: :maybe})

    assert detail =~ "verdict"

    assert {:error, %Error{reason: :invalid, detail: "invalid adapter: " <> _rest}} =
             Config.new(adapter: Enum)

    assert {:error, %Error{reason: :invalid, detail: "invalid adapter: " <> _rest}} =
             Config.new(adapter: Turnstile.NoSuchAdapter)
  end

  test "new/1 rejects options for an adapter that declares no schema" do
    assert {:ok, %Config{adapter: {NoOptions, []}}} = Config.new(adapter: NoOptions)

    assert {:error, %Error{reason: :invalid, detail: "invalid adapter: " <> detail}} =
             Config.new(adapter: {NoOptions, x: 1})

    assert detail =~ "takes no options"
  end

  test "new!/1 raises the error" do
    assert_raise Error, ~r/invalid config/, fn -> Config.new!([]) end
    assert %Config{} = Config.new!(adapter: Fake)
  end

  test "resolve/0 fails when nothing is booted and nothing is overridden" do
    assert {:error, %Error{reason: :invalid, detail: "invalid config: nothing booted and no override"}} = Config.resolve()
  end

  test "resolve/0 answers from the override alone" do
    Turnstile.Test.with_config(adapter: Fake)
    assert {:ok, %Config{adapter: {Fake, verdict: :deny}}} = Config.resolve()
  end

  test "resolve/0 merges the override onto the boot struct and round-trips through to_keyword/1" do
    booted = Config.boot!(adapter: Fake, caps: [policy_content_bytes: 512])
    assert Config.new!(Config.to_keyword(booted)) == booted
    assert {:ok, ^booted} = Config.resolve()

    Turnstile.Test.with_config([caps: [policy_content_bytes: 8]], fn ->
      assert {:ok, %Config{caps: [policy_content_bytes: 8]}} = Config.resolve()
    end)

    assert {:ok, ^booted} = Config.resolve()
  end

  test "resolve/0 reads the override from the $callers chain" do
    Turnstile.Test.with_config(adapter: {Fake, verdict: :allow})

    assert {:ok, %Config{adapter: {Fake, verdict: :allow}}} =
             Task.await(Task.async(fn -> Task.await(Task.async(&Config.resolve/0)) end))

    assert {:error, %Error{reason: :invalid}} =
             Task.await(Task.async(fn -> Process.delete(:"$callers") && Config.resolve() end))
  end

  test "with_config/2 restores the previous override even when the function raises" do
    Turnstile.Test.with_config(adapter: Fake)

    assert_raise RuntimeError, fn ->
      Turnstile.Test.with_config([caps: [policy_content_bytes: 8]], fn -> raise "boom" end)
    end

    assert {:ok, %Config{caps: [policy_content_bytes: 65_536]}} = Config.resolve()
  end

  test "override_key/0 names the process dictionary key" do
    assert Config.override_key() == Config
  end
end
