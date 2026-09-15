defmodule Example.Fixture.Rows do
  @moduledoc """
  What `Turnstile.Conformance.RepoCase` writes when the example holds its
  repo to the five guarantees: a document of the world's program, whose
  decontrol date is a fact field, under the fixture's exemption, with an
  UPDATE by hand as the write that goes around the seam; and a second such
  document, read under a decision the fake adapter allows.
  """

  @behaviour Turnstile.Conformance.RepoCase.Rows

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Example.Document
  alias Example.Fixture
  alias Example.Office
  alias Example.Program
  alias Example.Repo
  alias Turnstile.Conformance.RepoCase.Rows
  alias Turnstile.Dev.Sandbox
  alias Turnstile.Test.Fake

  @decontrolled ~U[2030-01-01 00:00:00Z]
  @by_hand ~U[2031-01-01 00:00:00Z]

  @impl Rows
  def setup(tags) when is_map(tags) do
    :ok = Sandbox.setup(Repo, tags)
    :ok = Turnstile.Test.with_config(adapter: {Fake, verdict: :allow})
    _world = Fixture.world!()
    :ok
  end

  @impl Rows
  def row do
    %Document{title: "conformance", program_id: first!(Program), designating_office_id: first!(Office)}
  end

  @impl Rows
  def change(%Document{} = document), do: Changeset.change(document, decontrol: @decontrolled)

  @impl Rows
  def mediation, do: Fixture.exemption()

  @impl Rows
  def around(%Document{id: id}) do
    sql = "UPDATE documents SET decontrol = $1 WHERE id = $2"
    _result = Repo.query!(sql, [@by_hand, id], turnstile: Fixture.exemption())
    :ok
  end

  @impl Rows
  def protected, do: row()

  @impl Rows
  def decision(%Document{id: id}) do
    {:ok, decision} = Turnstile.authorize({:user, "conformance"}, :read, {:document, id})
    decision
  end

  # The oldest row of a type the world wrote, which is the tenant a
  # conformance document belongs to.
  defp first!(schema) do
    query = from(row in schema, order_by: [asc: row.id], limit: 1, select: row.id)
    Repo.one!(query, turnstile: Fixture.exemption())
  end
end
