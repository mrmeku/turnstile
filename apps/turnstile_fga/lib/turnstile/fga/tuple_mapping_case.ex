defmodule Turnstile.Fga.TupleMappingCase do
  @moduledoc """
  The case template a tuple mapping is proved by. `use
  Turnstile.Fga.TupleMappingCase, mapping: MyApp.TupleMapping, repo:
  MyApp.Repo, population: MyApp.TupleMappingPopulation` defines a test module
  that holds the mapping to what a drain relies on.

  A drain reads what an object requires and writes the difference against
  what the store holds for that object, so the mapping owes it four things.
  Every object it names is of a type it declared, or the store holds tuples
  no reconcile reads. Every tuple an object requires names that object, or
  one object's drain writes what another object's drain takes away again. An
  object whose rows are gone requires nothing, or a deletion is never
  written. And a change to a row names every object whose tuples rest on
  that row, or the store keeps a tuple the tables stopped asking for until
  somebody reconciles.

  Nothing here talks to a server. The mapping is a reader of tables, and
  these are its own laws.

  Options:

  - `mapping:` the `Turnstile.Fga.TupleMapping` module, required.
  - `repo:` the mediated repo the mapping reads through, required.
  - `population:` the `Turnstile.Fga.Population` module, required.
  - `sandbox:` a module answering `setup(repo, tags)`, called first in every
    test, for a repo that needs a checkout before the test runs. Omit it for
    a repo that needs none.
  - `async:` default `true`.
  """

  import ExUnit.Assertions

  alias Turnstile.Change

  @doc false
  defmacro __using__(opts) do
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)

    config = %{
      mapping: Keyword.fetch!(opts, :mapping),
      repo: Keyword.fetch!(opts, :repo),
      population: Keyword.fetch!(opts, :population),
      sandbox: Keyword.get(opts, :sandbox)
    }

    [preamble(config, Keyword.get(opts, :async, true)), shape(), completeness()]
  end

  @doc false
  @spec __setup__(map(), map()) :: {:ok, keyword()}
  def __setup__(config, tags) do
    if config.sandbox, do: :ok = config.sandbox.setup(config.repo, tags)
    :ok = config.population.clear(config.repo)
    marked = marked(config, fn -> config.population.write(config.repo) end)

    {:ok, mapping_case: config, marked: marked}
  end

  @doc false
  @spec types_and_objects(map()) :: true
  def types_and_objects(config) do
    types = config.mapping.object_types()

    assert(types == Enum.uniq(types))
    assert(Enum.all?(types, &(is_binary(&1) and &1 != "")))

    Enum.each(types, fn type ->
      objects = config.mapping.objects(config.repo, type)

      assert(objects == Enum.uniq(objects))
      assert(Enum.all?(objects, &String.starts_with?(&1, type <> ":")))
    end)
  end

  @doc false
  @spec tuples_name_their_object(map()) :: true
  def tuples_name_their_object(config) do
    required = for object <- objects(config), tuple <- config.mapping.tuples(config.repo, object), do: {object, tuple}

    assert(required != [], "the population states no tuple, so there is nothing to hold the mapping to")
    assert(Enum.all?(required, fn {object, tuple} -> tuple.object == object end))
  end

  @doc false
  @spec absent_objects_require_nothing(map()) :: true
  def absent_objects_require_nothing(config) do
    absent = Enum.map(config.mapping.object_types(), fn type -> config.population.absent(type) end)

    assert(Enum.all?(absent, &(config.mapping.tuples(config.repo, &1) == [])))
  end

  @doc false
  @spec writing_marks_every_object(map(), MapSet.t()) :: true
  def writing_marks_every_object(config, marked) do
    wanted = for object <- objects(config), config.mapping.tuples(config.repo, object) != [], do: object

    assert(wanted != [], "the population states no tuple, so there is nothing to hold the mapping to")
    assert(MapSet.subset?(MapSet.new(wanted), marked), "unmarked: #{inspect(wanted -- MapSet.to_list(marked))}")
  end

  @doc false
  @spec clearing_marks_every_object(map()) :: true
  def clearing_marks_every_object(config) do
    held = for object <- objects(config), config.mapping.tuples(config.repo, object) != [], do: object
    marked = marked(config, fn -> config.population.clear(config.repo) end)

    assert(MapSet.subset?(MapSet.new(held), marked), "unmarked: #{inspect(held -- MapSet.to_list(marked))}")
    assert(Enum.all?(held, &(config.mapping.tuples(config.repo, &1) == [])))
  end

  @doc false
  @spec __change__([atom()], map(), map(), map()) :: :ok
  def __change__(_event, _measurements, payload, %{pid: pid, id: id}) do
    if self() == pid, do: send(pid, {id, payload})
    :ok
  end

  defp objects(config) do
    Enum.flat_map(config.mapping.object_types(), &config.mapping.objects(config.repo, &1))
  end

  # The objects the mapping marks for the changes the function published,
  # collected from the change event rather than from a payload written here,
  # so the mapping is asked what the seam actually says.
  defp marked(config, fun) do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(id, Change.event(), &__MODULE__.__change__/4, %{pid: self(), id: id})

    try do
      :ok = fun.()

      id
      |> collect([])
      |> Enum.flat_map(&config.mapping.changed(config.repo, &1))
      |> MapSet.new()
    after
      :telemetry.detach(id)
    end
  end

  defp collect(id, collected) do
    receive do
      {^id, one} -> collect(id, [one | collected])
    after
      0 -> Enum.reverse(collected)
    end
  end

  defp preamble(config, async) do
    quote do
      use ExUnit.Case, async: unquote(async)

      @mapping_case unquote(Macro.escape(config))

      setup tags do
        unquote(__MODULE__).__setup__(@mapping_case, tags)
      end
    end
  end

  defp shape do
    quote do
      test "the types are distinct and every object the mapping names is of the type it was asked for" do
        unquote(__MODULE__).types_and_objects(@mapping_case)
      end

      test "every tuple an object requires names that object" do
        unquote(__MODULE__).tuples_name_their_object(@mapping_case)
      end

      test "an object no row names requires no tuple" do
        unquote(__MODULE__).absent_objects_require_nothing(@mapping_case)
      end
    end
  end

  defp completeness do
    quote do
      test "writing the population marks every object that requires a tuple", %{marked: marked} do
        unquote(__MODULE__).writing_marks_every_object(@mapping_case, marked)
      end

      test "taking the population away marks every object it held tuples for, and each then requires none" do
        unquote(__MODULE__).clearing_marks_every_object(@mapping_case)
      end
    end
  end
end
