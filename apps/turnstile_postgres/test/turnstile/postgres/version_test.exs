defmodule Turnstile.Postgres.VersionTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Memory
  alias Turnstile.PolicyVersion
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Policy
  alias Turnstile.Postgres.Version
  alias Turnstile.Postgres.VersionTest.Refusing
  alias Turnstile.Subject

  @policies [
    %Policy{name: "turnstile_scope_read", table: "folders", command: :select, using: "true", with_check: nil},
    %Policy{name: "turnstile_gate_edit", table: "folders", command: :update, using: "false", with_check: "false"},
    %Policy{name: "turnstile_scope_read", table: "items", command: :select, using: "true", with_check: nil}
  ]

  setup do
    agent = start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})
    {:ok, ledger: {Memory, agent: agent}}
  end

  test "the version is the migration number and carries the policies as text" do
    at = DateTime.utc_now()
    version = version(at: at)

    assert %PolicyVersion{adapter: Turnstile.Postgres, version: "20260101000001"} = version
    assert {version.author, version.approval, version.at} == {"turnstile_postgres", "the conformance suite", at}
    assert version.content == Catalog.to_text(@policies)
    assert version.content_hash =~ ~r/\A[0-9a-f]{64}\z/
    assert version.pointer == nil
  end

  test "over the content cap the version points at the tables and hashes the text all the same" do
    version = version(content_bytes: 8)

    assert version.content == nil
    assert version.pointer == "policies on folders, items"
    assert version.content_hash == version().content_hash
  end

  test "in ledger mode none publish emits telemetry alone" do
    :telemetry.attach(inspect(self()), Version.telemetry_event(), &__MODULE__.forward/4, self())

    assert Version.publish(version(), :none) == {:ok, :telemetry}
    assert_receive {:policy_version, %{version: %PolicyVersion{version: "20260101000001"}, result: :telemetry}}
  after
    :telemetry.detach(inspect(self()))
  end

  test "publish appends one event per version, never per migration run", %{ledger: ledger} do
    assert {:ok, %FactEvent{} = event} = Version.publish(version(), ledger)

    assert {event.kind, event.subject_ref, event.object_ref} == {:policy_version, nil, {:policy, Turnstile.Postgres}}
    assert {event.attribute, event.old, event.position} == {:version, nil, 1}
    assert %PolicyVersion{version: "20260101000001"} = event.new
    assert event.by == Subject.library()

    assert Version.publish(version(), ledger) == {:ok, :current}
  end

  test "a newer migration records the previous version as old", %{ledger: ledger} do
    assert {:ok, %FactEvent{old: nil}} = Version.publish(version(), ledger)

    assert {:ok, %FactEvent{old: "20260101000001", new: %PolicyVersion{version: "20260202000002"}}} =
             Version.publish(version(version: 20_260_202_000_002), ledger)
  end

  test "a ledger that refuses the read is the error, inside the transaction it opened" do
    assert Version.publish(version(), {Refusing, on: :read}) == {:error, engine("read refused")}
  end

  test "a ledger that refuses the append is the error" do
    assert Version.publish(version(), {Refusing, on: :append}) == {:error, engine("append refused")}
  end

  @doc false
  @spec forward([atom()], map(), map(), pid()) :: :ok
  def forward(_event, _measurements, metadata, pid) do
    send(pid, {:policy_version, metadata})
    :ok
  end

  defp version(overrides \\ []) do
    options = [
      version: 20_260_101_000_001,
      author: "turnstile_postgres",
      approval: "the conformance suite",
      at: DateTime.utc_now(),
      content_bytes: 65_536
    ]

    Version.of(Turnstile.Postgres, @policies, Keyword.merge(options, overrides))
  end

  defp engine(detail) do
    %Error.Engine{adapter: Refusing, operation: :publish, detail: detail}
  end

  defmodule Refusing do
    @moduledoc "A ledger that runs its work in a transaction and refuses the call the options name."

    @behaviour Turnstile.Ledger

    @doc "Run the function, so the transaction branch of `publish/2` is the one taken."
    @spec transaction(keyword(), (-> result)) :: result when result: term()
    def transaction(_options, fun), do: fun.()

    @impl Turnstile.Ledger
    def options_schema, do: NimbleOptions.new!(on: [type: :atom, required: true])

    @impl Turnstile.Ledger
    def append(options, _events), do: refuse(options, :append)

    @impl Turnstile.Ledger
    def read(options, _from, _limit), do: refuse(options, :read) || {:ok, []}

    @impl Turnstile.Ledger
    def head(_options), do: {:ok, 0}

    defp refuse(options, call) do
      if Keyword.fetch!(options, :on) == call do
        {:error, %Error.Engine{adapter: __MODULE__, operation: :publish, detail: "#{call} refused"}}
      end
    end
  end
end
