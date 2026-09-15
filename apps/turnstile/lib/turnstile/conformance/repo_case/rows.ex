defmodule Turnstile.Conformance.RepoCase.Rows do
  @moduledoc """
  What an adopter gives `Turnstile.Conformance.RepoCase` so the case can
  hold a repo to the five guarantees the change and access events make: a
  row of one audited schema, a change to one of its fact fields, the
  mediation those writes carry, the way this deployment writes the same
  row without passing the seam, and a row of one protected schema with a
  decision that admits reading it.

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

  @doc "An unwritten row of a protected schema, one that declares an object type, for the access guarantee."
  @callback protected() :: struct()

  @doc "A decision from `Turnstile.authorize/4` that admits reading the written row of `protected/0`."
  @callback decision(struct()) :: Turnstile.Decision.t()

  @optional_callbacks setup: 1
end
