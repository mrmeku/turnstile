defmodule Turnstile.Postgres.Adapter.Version do
  @moduledoc false
  # Publishing the policy version: one telemetry event per call, carrying
  # the version. Nothing is stored, so the event is the whole of what a
  # publication leaves behind, and the name of the event is here, beside
  # the one place that emits it. What a version is, and what it holds, is
  # `Turnstile.Postgres.Version`'s.

  alias Turnstile.PolicyVersion

  @telemetry [:turnstile, :postgres, :policy_version]

  @doc "The event `publish/1` emits, which `Turnstile.Postgres.Version.telemetry_event/0` answers with."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry

  @doc "Emit the version, once per call, answering the version emitted."
  @spec publish(PolicyVersion.t()) :: {:ok, PolicyVersion.t()}
  def publish(%PolicyVersion{} = version) do
    :telemetry.execute(@telemetry, %{}, %{version: version})

    {:ok, version}
  end
end
