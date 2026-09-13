defmodule Turnstile.Conformance.RepoCase.Rows do
  @moduledoc """
  What an adopter gives `Turnstile.Conformance.RepoCase` so the case can
  hold a repo to the four guarantees the change event makes: a row of one
  audited schema, a change to one of its fact fields, the mediation those
  writes carry, and the way this deployment writes the same row without
  passing the seam.

  The schema's table has to exist, because the case writes to it. A repo
  swept without a database leaves the option out and proves the refusals
  alone.
  """

  @doc """
  Whatever a test needs in place first: the connection, the configuration,
  and the rows the audited schema refers to. The tags are the test's. An
  adopter that needs none of it defines this not at all.
  """
  @callback setup(tags :: map()) :: :ok

  @doc "An unwritten row of an audited schema. Each call answers one that can be written beside the ones before it."
  @callback row() :: struct()

  @doc "A change of a written row that sets at least one fact field to a value the row does not hold."
  @callback change(struct()) :: Ecto.Changeset.t()

  @doc "The `turnstile:` option those writes carry: a decision that admits the schema, or a declared exemption."
  @callback mediation() :: term()

  @doc "Change a fact field of the written row without passing the seam, as a patch applied by hand does."
  @callback around(struct()) :: :ok

  @optional_callbacks setup: 1
end
