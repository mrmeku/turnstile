defmodule Turnstile.Conformance.RepoCase do
  @moduledoc """
  The conformance case for a repo: `use Turnstile.Conformance.RepoCase,
  repo: MyApp.Repo` writes the tests that hold the repo to the seam. The
  repo must answer `__turnstile__/1`, export nothing outside the surface it
  was compiled against, and refuse every query, write, and raw call on a
  protected schema that carries no decision and no exemption, before any
  SQL. The repo is started; the protected schema's
  table need not exist.

      defmodule MyApp.RepoTest do
        use Turnstile.Conformance.RepoCase, repo: MyApp.Repo
      end

  An adopter that names a `Turnstile.Conformance.RepoCase.Rows` module as
  well gets four more tests, one per guarantee the change event makes: a
  single-row write to an audited schema emits one event carrying every fact
  field that changed, a bulk write to one raises and emits nothing, a write
  that goes around the seam emits nothing, and a handler that writes to the
  same repo joins the write's transaction. Those four write to the
  database the rows module names.

      defmodule MyApp.RepoTest do
        use Turnstile.Conformance.RepoCase, repo: MyApp.Repo, rows: MyApp.RepoRows
      end
  """

  import ExUnit.Assertions

  alias Turnstile.Change
  alias Turnstile.Conformance.RepoCase
  alias Turnstile.Core.Surface
  alias Turnstile.Schema
  alias Turnstile.Test

  @joined {__MODULE__, :joined}

  @doc false
  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    async = Keyword.get(opts, :async, true)
    rows = Keyword.get(opts, :rows)

    quote bind_quoted: [repo: repo, async: async, rows: rows] do
      use ExUnit.Case, async: async

      @turnstile_repo repo
      @turnstile_rows rows

      test "the repo answers __turnstile__/1 and exports only what the surface it was compiled against classifies" do
        RepoCase.assert_surface(@turnstile_repo)
      end

      for {name, arity} <- RepoCase.swept(repo) do
        @turnstile_call {name, arity}

        test "Repo.#{name}/#{arity} on a protected schema without a decision or an exemption is refused before SQL" do
          RepoCase.assert_refused(@turnstile_repo, @turnstile_call)
        end
      end

      if rows do
        setup tags do
          RepoCase.setup_rows(@turnstile_rows, tags)
        end

        test "E1 a single-row write to an audited schema emits one change event, carrying every fact field that changed" do
          RepoCase.assert_one_change(@turnstile_repo, @turnstile_rows)
        end

        test "E2 a bulk write to an audited schema raises and emits nothing" do
          RepoCase.assert_bulk_refused(@turnstile_repo, @turnstile_rows)
        end

        test "E3 a write that goes around the interception emits nothing" do
          RepoCase.assert_around_silent(@turnstile_repo, @turnstile_rows)
        end

        test "E4 a consumer that writes to the same repository from its handler joins the write transaction" do
          RepoCase.assert_handler_joins(@turnstile_repo, @turnstile_rows)
        end
      end
    end
  end

  @doc "Fails unless the repo answers `__turnstile__/1` and exports only classified functions."
  @spec assert_surface(module()) :: :ok
  def assert_surface(repo) when is_atom(repo) do
    if !(Code.ensure_loaded?(repo) and function_exported?(repo, :__turnstile__, 1)) do
      flunk("#{inspect(repo)} does not use Turnstile.Repo")
    end

    classified = MapSet.new(Surface.all(), fn {name, arity, _bucket} -> {name, arity} end)

    case Enum.reject(repo.__info__(:functions), &MapSet.member?(classified, &1)) do
      [] -> :ok
      [{name, arity} | _rest] -> flunk(unclassified(repo, name, arity))
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

    assert_raise(Turnstile.Error, fn ->
      case apply(repo, name, args) do
        %Stream{} = stream -> Enum.to_list(stream)
        stream when is_function(stream) -> Enum.to_list(stream)
        other -> other
      end
    end)

    :ok
  end

  @doc "The rows module's own setup, where it defines one."
  @spec setup_rows(module(), map()) :: :ok
  def setup_rows(rows, tags) when is_atom(rows) and is_map(tags) do
    if Code.ensure_loaded?(rows) and function_exported?(rows, :setup, 1), do: rows.setup(tags), else: :ok
  end

  @doc "E1: one event for the insert, one for the update, and the fact fields the update changed."
  @spec assert_one_change(module(), module()) :: :ok
  def assert_one_change(repo, rows) when is_atom(repo) and is_atom(rows) do
    {row, created} = Test.changes(fn -> repo.insert!(rows.row(), turnstile: rows.mediation()) end)
    assert [%{operation: :create}] = created

    changeset = rows.change(row)
    {_updated, changed} = Test.changes(fn -> repo.update!(changeset, turnstile: rows.mediation()) end)
    assert [event] = changed
    assert_updated(event, rows, row, changeset)
  end

  @doc "E2: every bulk call the repo exports raises on an audited schema, and none of them publishes."
  @spec assert_bulk_refused(module(), module()) :: :ok
  def assert_bulk_refused(repo, rows) when is_atom(repo) and is_atom(rows) do
    row = repo.insert!(rows.row(), turnstile: rows.mediation())
    sets = Enum.to_list(rows.change(row).changes)

    {_refusals, changes} =
      Test.changes(fn -> Enum.each(bulk(row.__struct__, sets), &assert_bulk(repo, rows, &1)) end)

    assert changes == []
    :ok
  end

  @doc "E3: a write the seam never saw publishes nothing, and it did reach the row."
  @spec assert_around_silent(module(), module()) :: :ok
  def assert_around_silent(repo, rows) when is_atom(repo) and is_atom(rows) do
    row = repo.insert!(rows.row(), turnstile: rows.mediation())
    {:ok, changes} = Test.changes(fn -> rows.around(row) end)
    read = repo.get!(row.__struct__, id(row), turnstile: rows.mediation())

    assert changes == []
    refute facts(read) == facts(row), "#{inspect(rows)}.around/1 left the row as it was"
    :ok
  end

  @doc "E4: the handler's own write is in the transaction the write opened, so a rollback takes it too."
  @spec assert_handler_joins(module(), module()) :: :ok
  def assert_handler_joins(repo, rows) when is_atom(repo) and is_atom(rows) do
    schema = rows.row().__struct__
    counted = repo.aggregate(schema, :count, turnstile: rows.mediation())
    handler = {__MODULE__, make_ref()}
    config = %{repo: repo, rows: rows, pid: self()}
    :ok = :telemetry.attach(handler, Change.event(), &__MODULE__.__join__/4, config)

    try do
      assert repo.transaction(fn -> discarded(repo, rows) end) == {:error, :discarded}
      assert Process.get(@joined) == true, "the handler's write ran outside the write's transaction"
    after
      :telemetry.detach(handler)
      Process.delete(@joined)
    end

    assert repo.aggregate(schema, :count, turnstile: rows.mediation()) == counted
    :ok
  end

  @doc false
  @spec __join__([atom()], map(), map(), map()) :: :ok
  def __join__(_event, _measurements, _payload, %{repo: repo, rows: rows, pid: pid}) do
    if self() == pid and is_nil(Process.get(@joined)) do
      Process.put(@joined, repo.in_transaction?())
      _row = repo.insert!(rows.row(), turnstile: rows.mediation())
    end

    :ok
  end

  # A write and a rollback of the transaction it ran in: what the handler
  # wrote goes with it, because it was the same transaction.
  defp discarded(repo, rows) do
    _row = repo.insert!(rows.row(), turnstile: rows.mediation())
    repo.rollback(:discarded)
  end

  defp assert_bulk(repo, rows, {name, args}) do
    if function_exported?(repo, name, length(args)) do
      error = assert_raise(Turnstile.Error, fn -> apply(repo, name, mediated(args, rows.mediation())) end)
      assert Exception.message(error) =~ "bulk write to an audited schema"
    end
  end

  defp bulk(schema, sets) do
    [
      {:update_all, [schema, [set: sets], []]},
      {:delete_all, [schema, []]},
      {:insert_all, [schema, [Map.new(sets)], []]}
    ]
  end

  defp mediated(args, mediation), do: List.replace_at(args, -1, turnstile: mediation)

  # The one event the update made, against the row it was made from.
  defp assert_updated(event, rows, row, changeset) do
    assert event.operation == :update
    assert event.schema == row.__struct__
    assert event.changes == expected(rows, row, changeset)
    assert event.target == {type(row.__struct__), id(row)}
    :ok
  end

  # What the event has to carry: every fact field the change sets, from the
  # value the row held to the value it is given.
  defp expected(rows, row, %Ecto.Changeset{changes: changes}) do
    schema = row.__struct__
    columns = Enum.filter(Schema.fact_columns(schema), &Map.has_key?(changes, &1))

    if columns == [] do
      flunk("#{inspect(rows)}.change/1 sets no fact field of #{inspect(schema)}")
    end

    Map.new(columns, &{&1, {Map.get(row, &1), Map.fetch!(changes, &1)}})
  end

  defp facts(row), do: Map.take(row, Schema.fact_columns(row.__struct__))

  defp type(schema), do: Schema.object_type_of(schema) || Schema.kind_of(schema)

  defp id(row) do
    case row.__struct__.__schema__(:primary_key) do
      [key] -> Map.fetch!(row, key)
      keys -> Map.new(keys, &{&1, Map.fetch!(row, &1)})
    end
  end

  defp unclassified(repo, name, arity) do
    "#{inspect(repo)} exports #{name}/#{arity}, which the surface this build was written against " <>
      "does not classify; " <>
      "a repo function outside the surface runs unchecked"
  end
end
