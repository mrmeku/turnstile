defmodule Turnstile.Repo.SurfaceTest.ExtraRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :turnstile_core, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo

  @doc false
  @spec extra(term()) :: term()
  def extra(x), do: x
end

defmodule Turnstile.Repo.SurfaceTest.ReadOnlyRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :turnstile_core, adapter: Ecto.Adapters.Postgres, read_only: true
  use Turnstile.Repo
end

defmodule Turnstile.Repo.SurfaceTest.ReadOnlyRepoCase do
  @moduledoc false
  use Turnstile.Conformance.RepoCase, repo: Turnstile.Repo.SurfaceTest.ReadOnlyRepo, async: true

  alias Turnstile.Conformance.RepoCase
  alias Turnstile.Repo.SurfaceTest.ReadOnlyRepo

  setup_all do
    config = Application.get_env(:turnstile_core, Turnstile.TestRepos.Sandboxed)
    start_supervised!({ReadOnlyRepo, config})
    :ok
  end

  test "a read-only repo exports a subset of the surface and passes the surface assertion" do
    refute function_exported?(ReadOnlyRepo, :insert, 2)
    assert :ok = RepoCase.assert_surface(ReadOnlyRepo)
  end
end

defmodule Turnstile.Repo.SurfaceTest do
  use ExUnit.Case, async: true

  alias Turnstile.Conformance.RepoCase
  alias Turnstile.Repo.Surface
  alias Turnstile.Repo.SurfaceTest.ExtraRepo
  alias Turnstile.TestRepos.Owner
  alias Turnstile.TestRepos.Sandboxed

  test "every surface entry sits in exactly one bucket and the buckets cover the pinned Ecto's exports" do
    all = Surface.all()
    assert Enum.uniq_by(all, fn {name, arity, _bucket} -> {name, arity} end) == all
    exported = Enum.sort(Sandboxed.__info__(:functions))

    assert exported ==
             all
             |> Enum.map(fn {n, a, _b} -> {n, a} end)
             |> Enum.sort()

    assert Surface.bucket(:all, 2) == :query
    assert Surface.bucket(:insert, 2) == :write
    assert Surface.bucket(:query, 3) == :raw
    assert Surface.bucket(:transaction, 2) == :plumbing
    assert Surface.bucket(:extra, 1) == nil
  end

  test "a repo exporting a function outside the surface fails with the function's name and arity" do
    assert_raise ExUnit.AssertionError, ~r/exports extra\/1, which Turnstile.Repo.Surface does not classify/, fn ->
      RepoCase.assert_surface(ExtraRepo)
    end
  end

  test "a repo without the seam fails the surface assertion" do
    assert_raise ExUnit.AssertionError, ~r/does not use Turnstile.Repo/, fn -> RepoCase.assert_surface(Enum) end
  end

  test "use Turnstile.Repo before use Ecto.Repo raises at compile time" do
    assert_raise ArgumentError, ~r/use Turnstile.Repo must follow use Ecto.Repo/, fn ->
      Code.compile_quoted(
        quote do
          defmodule Turnstile.Repo.SurfaceTest.WrongOrder do
            @moduledoc false
            use Turnstile.Repo
            use Ecto.Repo, otp_app: :turnstile_core, adapter: Ecto.Adapters.Postgres
          end
        end
      )
    end
  end

  test "use Turnstile.Repo validates its role" do
    assert_raise NimbleOptions.ValidationError, fn ->
      Code.compile_quoted(
        quote do
          defmodule Turnstile.Repo.SurfaceTest.BadRole do
            @moduledoc false
            use Ecto.Repo, otp_app: :turnstile_core, adapter: Ecto.Adapters.Postgres
            use Turnstile.Repo, role: :tenant
          end
        end
      )
    end
  end

  test "the bucket readers partition the surface and bucket/2 answers by name and arity" do
    listed = Surface.query() ++ Surface.write() ++ Surface.raw() ++ Surface.plumbing()
    assert Enum.sort(listed) == Enum.sort(Enum.map(Surface.all(), fn {n, a, _b} -> {n, a} end))
    assert Surface.bucket(:all, 2) == :query
    assert Surface.bucket(:insert, 2) == :write
    assert Surface.bucket(:query, 3) == :raw
    assert Surface.bucket(:transaction, 2) == :plumbing
    assert Surface.bucket(:extra, 1) == nil
  end

  test "the repos answer their role" do
    assert Sandboxed.__turnstile__(:role) == :app
    assert Owner.__turnstile__(:role) == :owner
  end
end
