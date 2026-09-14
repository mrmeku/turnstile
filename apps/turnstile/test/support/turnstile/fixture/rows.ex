defmodule Turnstile.Fixture.Rows do
  @moduledoc """
  What `Turnstile.Conformance.RepoCase` writes when core holds its own
  sandboxed repo to the four guarantees: a membership, whose role is a fact
  field, under a declared exemption, with an UPDATE by hand as the write
  that goes around the seam.
  """

  @behaviour Turnstile.Conformance.RepoCase.Rows

  alias Ecto.Changeset
  alias Turnstile.Conformance.RepoCase.Rows
  alias Turnstile.Fixture.Membership
  alias Turnstile.Test.Fake
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  @exempt {:exempt, "conformance: the rows the repo case writes"}

  @impl Rows
  def setup(tags) when is_map(tags) do
    :ok = Sandbox.setup(Sandboxed, tags)
    Turnstile.Test.with_config(adapter: Fake)
  end

  @impl Rows
  def row, do: %Membership{account_id: "conformance", role: :reader}

  @impl Rows
  def change(%Membership{} = membership), do: Changeset.change(membership, role: :editor)

  @impl Rows
  def mediation, do: @exempt

  @impl Rows
  def around(%Membership{id: id}) do
    sql = "UPDATE turnstile_fixture_memberships SET role = 'editor' WHERE id = $1"
    _result = Sandboxed.query!(sql, [id], turnstile: @exempt)
    :ok
  end
end
