defmodule Turnstile.Conformance.Versions do
  @moduledoc """
  What the `cm3` laws need and a law cannot write without naming the
  adapter: how this adapter publishes a policy version, how a rule is
  tightened on it, and how the original is put back. Passed to
  `Turnstile.Conformance.AdapterCase` as `versions:`; a template given none
  runs the `cm3` laws as skipped, with the reason printed.

  The tightened version is the one the laws measure propagation against:
  after `tighten/0` the subject `focus/1` of the granted world names, which
  holds an editor's grant, is denied the first operation the world knows.
  `restore/0` puts the original rule back and returns once it is in force
  again, since the next law asks with no poll of its own.

  These laws write on the committed repo, because a version on some
  adapters is a statement the sandbox's transaction would block.
  """

  alias Turnstile.PolicyVersion

  @doc "The telemetry event the adapter publishes a policy version on."
  @callback event() :: [atom()]

  @doc "Publish a version that excludes the granted editor from reading, and answer the version published."
  @callback tighten() :: {:ok, PolicyVersion.t()} | {:error, Turnstile.Error.t()}

  @doc "Put the original rule back, and return once it is in force."
  @callback restore() :: :ok

  @doc "Prepare an engine that keeps state per test, given the test's tags."
  @callback setup(map()) :: :ok

  @optional_callbacks setup: 1
end
