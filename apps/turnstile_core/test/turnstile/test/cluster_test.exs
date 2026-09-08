defmodule Turnstile.Test.ClusterTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias Turnstile.Test.Cluster
  alias Turnstile.TestRepos.Committed
  alias Turnstile.TestRepos.Owner
  alias Turnstile.TestRepos.Sandboxed

  setup tags do
    Turnstile.Test.Sandbox.setup(Sandboxed, tags)
  end

  test "the sandboxed repo answers a query as the application role" do
    assert %{rows: [["turnstile_app", "turnstile_test"]]} =
             SQL.query!(Sandboxed, "SELECT current_user::text, current_database()::text")
  end

  test "the application role cannot bypass row level security" do
    assert %{rows: [[false]]} =
             SQL.query!(Sandboxed, "SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user")
  end

  test "the committed and owner repos share the committed database" do
    assert %{rows: [["turnstile_app", "turnstile_committed"]]} =
             SQL.query!(Committed, "SELECT current_user::text, current_database()::text")

    assert %{rows: [["turnstile_owner", "turnstile_committed"]]} =
             SQL.query!(Owner, "SELECT current_user::text, current_database()::text")
  end

  test "the cluster lives under tmp in the app directory and listens on no TCP port" do
    cluster = Cluster.info()
    assert String.starts_with?(cluster.dir, Path.join(File.cwd!(), "tmp/pg-"))
    assert File.dir?(cluster.data_dir)
    assert %{rows: [[""]]} = SQL.query!(Owner, "SHOW listen_addresses")
  end

  test "poll returns the first truthy value and raises after the deadline" do
    counter = :counters.new(1, [])

    assert 3 =
             Turnstile.Test.poll(fn ->
               :counters.add(counter, 1, 1)
               if :counters.get(counter, 1) >= 3, do: :counters.get(counter, 1)
             end)

    assert_raise RuntimeError, ~r/poll timed out/, fn -> Turnstile.Test.poll(fn -> nil end, 30) end
  end
end
