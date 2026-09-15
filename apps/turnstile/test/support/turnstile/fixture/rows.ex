defmodule Turnstile.Fixture.Rows do
  @moduledoc """
  What `Turnstile.Conformance.RepoCase` writes when core holds its own
  sandboxed repo to the five guarantees: a membership, whose role is a fact
  field, under a declared exemption, with an UPDATE by hand as the write
  that goes around the seam; and a folder, read under a decision the fake
  adapter allows.
  """

  @behaviour Turnstile.Conformance.RepoCase.Rows

  alias Ecto.Changeset
  alias Turnstile.Conformance.RepoCase.Rows
  alias Turnstile.Dev.Sandbox
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership
  alias Turnstile.Test.Fake
  alias Turnstile.TestRepos.Sandboxed

  @exempt {:exempt, "conformance: the rows the repo case writes"}

  @impl Rows
  def setup(tags) when is_map(tags) do
    :ok = Sandbox.setup(Sandboxed, tags)
    Turnstile.Test.with_config(adapter: {Fake, verdict: :allow})
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

  @impl Rows
  def protected, do: %Folder{name: "conformance"}

  @impl Rows
  def decision(%Folder{id: id}) do
    {:ok, decision} = Turnstile.authorize({:user, "conformance"}, :read, {:folder, id})
    decision
  end
end
