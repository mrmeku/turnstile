defmodule Turnstile.Conformance.RepoCase do
  @moduledoc """
  The conformance case for a repo: `use Turnstile.Conformance.RepoCase,
  repo: MyApp.Repo` writes the tests that hold the repo to the seam. The
  repo must answer `__turnstile__/1`, export nothing
  `Turnstile.Repo.Surface` does not classify, and refuse every query,
  write, and raw call on a protected schema that carries no decision and no
  exemption, before any SQL. The repo is started; the protected schema's
  table need not exist.

      defmodule MyApp.RepoTest do
        use Turnstile.Conformance.RepoCase, repo: MyApp.Repo
      end
  """

  alias Turnstile.Conformance.RepoCase
  alias Turnstile.Repo.Surface

  @doc false
  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    async = Keyword.get(opts, :async, true)

    quote bind_quoted: [repo: repo, async: async] do
      use ExUnit.Case, async: async

      @turnstile_repo repo

      test "the repo answers __turnstile__/1 and exports only what Turnstile.Repo.Surface classifies" do
        RepoCase.assert_surface(@turnstile_repo)
      end

      for {name, arity} <- RepoCase.swept(repo) do
        @turnstile_call {name, arity}

        test "Repo.#{name}/#{arity} on a protected schema without a decision or an exemption is refused before SQL" do
          RepoCase.assert_refused(@turnstile_repo, @turnstile_call)
        end
      end
    end
  end

  @doc "Fails unless the repo answers `__turnstile__/1` and exports only classified functions."
  @spec assert_surface(module()) :: :ok
  def assert_surface(repo) when is_atom(repo) do
    if !(Code.ensure_loaded?(repo) and function_exported?(repo, :__turnstile__, 1)) do
      ExUnit.Assertions.flunk("#{inspect(repo)} does not use Turnstile.Repo")
    end

    classified = MapSet.new(Surface.all(), fn {name, arity, _bucket} -> {name, arity} end)

    case Enum.reject(repo.__info__(:functions), &MapSet.member?(classified, &1)) do
      [] -> :ok
      [{name, arity} | _rest] -> ExUnit.Assertions.flunk(unclassified(repo, name, arity))
    end
  end

  @doc "The query, write, and raw functions the repo exports, each swept with fixture arguments."
  @spec swept(module()) :: [{atom(), non_neg_integer()}]
  def swept(repo) when is_atom(repo) do
    exported = MapSet.new(repo.__info__(:functions))

    for {name, arity, bucket} <- Surface.all(), bucket != :plumbing, MapSet.member?(exported, {name, arity}) do
      {name, arity}
    end
  end

  @doc "Calls the function with fixture arguments on the protected schema and expects the refusal."
  @spec assert_refused(module(), {atom(), non_neg_integer()}) :: :ok
  def assert_refused(repo, {name, arity}) when is_atom(repo) do
    args = RepoCase.Fixture.args(name, arity)

    ExUnit.Assertions.assert_raise(Turnstile.Error.Unmediated, fn ->
      case apply(repo, name, args) do
        %Stream{} = stream -> Enum.to_list(stream)
        stream when is_function(stream) -> Enum.to_list(stream)
        other -> other
      end
    end)

    :ok
  end

  defp unclassified(repo, name, arity) do
    "#{inspect(repo)} exports #{name}/#{arity}, which Turnstile.Repo.Surface does not classify; " <>
      "a repo function outside the surface runs unchecked"
  end
end
