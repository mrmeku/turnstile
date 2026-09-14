defmodule Turnstile.Postgres.VersionTest do
  use ExUnit.Case, async: true

  alias Turnstile.PolicyVersion
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Policy
  alias Turnstile.Postgres.Version

  @policies [
    %Policy{name: "turnstile_scope_read", table: "folders", command: :select, using: "true", with_check: nil},
    %Policy{name: "turnstile_gate_edit", table: "folders", command: :update, using: "false", with_check: "false"},
    %Policy{name: "turnstile_scope_read", table: "items", command: :select, using: "true", with_check: nil}
  ]

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

  test "publish emits one event per call, carrying the version" do
    :telemetry.attach(inspect(self()), Version.telemetry_event(), &__MODULE__.forward/4, self())

    assert {:ok, %PolicyVersion{version: "20260101000001"} = version} = Version.publish(version())
    assert_receive {:policy_version, %{version: ^version}}
    refute_receive {:policy_version, _later}
  after
    :telemetry.detach(inspect(self()))
  end

  test "a newer migration publishes under its own number" do
    assert {:ok, %PolicyVersion{version: "20260101000001"}} = Version.publish(version())

    assert {:ok, %PolicyVersion{version: "20260202000002"}} =
             Version.publish(version(version: 20_260_202_000_002))
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
end
