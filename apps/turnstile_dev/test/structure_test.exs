defmodule StructureTest do
  @moduledoc """
  One rule over every compiled source file in the umbrella: the file's path
  names a module the file defines, and every other module the file defines
  is named under that one. A reader who knows a module's name knows which
  file holds it, and a reader who opens a file knows which module to expect.

  The roots are each package's `lib` and `test/support`, the two trees the
  compiler is given. A path names a module when the module's name,
  underscored, is the path under its root without its extension, with the
  Mix convention for a task file: the dots in the last segment stand for the
  dots in the name, so `lib/mix/tasks/turnstile.schema_dump.ex` names
  `Mix.Tasks.Turnstile.SchemaDump`.

  Four more rules over the three interior places `docs/design.md` §6 gives a
  package. A module under `domain/` is what the package knows: it calls
  nothing that touches a process, a file, a clock, a table, or a node, and it
  names no module under `application/` or `infrastructure/`. A module under
  `infrastructure/` names no module under `application/`, so the calls inside
  a package run one way. In a published package a module under any of the
  three places carries `@moduledoc false`, because none of them is the
  interface; the example and the thin applications keep their docs, because
  their layers are what a reader opens them for.

  The test reads the syntax tree rather than the compiled modules, so it
  starts nothing and depends on nothing it reads. The `boundary` library
  cannot see a call to Elixir's own modules or to Erlang, which is why the
  effect rule is read here and not from a dependency list.

  `@exceptions` names each file that cannot follow the path rule, with its
  reason. `docs/design.md` §6 states the rules and the two dependency gates that
  shape the first.
  """

  use ExUnit.Case, async: true

  @umbrella Path.expand("../../..", __DIR__)

  # The packages that ship to Hex, whose interior is not their interface.
  @published ~w(turnstile turnstile_rbac turnstile_postgres turnstile_cerbos turnstile_fga)

  @exceptions %{
    "apps/example/lib/example/domain/document.ex" =>
      "a document, its markings, its portions, and its proposals refer to one another"
  }

  # The modules of Elixir and of Erlang whose functions reach outside the
  # call: a process, a file, a clock, a table, a node, or the log.
  @world ~w(
    Agent Application Code DynamicSupervisor Ecto.Adapters.SQL Ecto.Migrator File GenServer IO
    Logger Mix Module Node Port Process Registry StringIO Supervisor System Task
  )

  @erlang [
    :application,
    :atomics,
    :code,
    :counters,
    :dets,
    :erlang,
    :ets,
    :file,
    :global,
    :httpc,
    :logger,
    :mnesia,
    :os,
    :persistent_term,
    :rand,
    :telemetry,
    :timer
  ]

  # The functions of the modules above that answer from their arguments
  # alone. A hash reaches nothing outside the call: the same term answers the
  # same number on any node and on any release, so a module that decides may
  # take one.
  @pure [{:erlang, :phash2}]

  # A moment read from a clock, whichever module answers it.
  @moments [
    :local_time,
    :monotonic_time,
    :system_time,
    :timestamp,
    :unique_integer,
    :universal_time,
    :utc_now,
    :utc_today
  ]

  # The `Kernel` forms that speak to a process or to the node.
  @forms [:exit, :make_ref, :node, :self, :send, :spawn, :spawn_link, :spawn_monitor]

  test "a file's path names a module it defines, and its other modules are named under that one" do
    violations =
      @umbrella
      |> source_files()
      |> Enum.reject(&is_map_key(@exceptions, Path.relative_to(&1, @umbrella)))
      |> Enum.flat_map(&violations_of/1)

    assert violations == [], "\n" <> Enum.join(violations, "\n") <> "\n"
  end

  test "a module in domain/ makes no call to the outside world" do
    violations = Enum.flat_map(place_files("domain"), &effects_of/1)

    assert violations == [], "\n" <> Enum.join(violations, "\n") <> "\n"
  end

  test "a module in domain/ names no module in application/ or infrastructure/" do
    violations =
      Enum.flat_map(["application", "infrastructure"], fn place ->
        modules = place_modules(place)
        Enum.flat_map(place_files("domain"), &named_from(&1, modules, place))
      end)

    assert violations == [], "\n" <> Enum.join(violations, "\n") <> "\n"
  end

  test "a module in infrastructure/ names no module in application/" do
    modules = place_modules("application")
    violations = Enum.flat_map(place_files("infrastructure"), &named_from(&1, modules, "application"))

    assert violations == [], "\n" <> Enum.join(violations, "\n") <> "\n"
  end

  test "a module in domain/, application/, or infrastructure/ of a published package carries @moduledoc false" do
    violations =
      ["domain", "application", "infrastructure"]
      |> Enum.flat_map(&place_files/1)
      |> Enum.filter(&published?/1)
      |> Enum.flat_map(&undocumented/1)

    assert violations == [], "\n" <> Enum.join(violations, "\n") <> "\n"
  end

  defp source_files(umbrella) do
    ["apps/*/lib", "apps/*/test/support"]
    |> Enum.flat_map(&Path.wildcard(Path.join(umbrella, &1)))
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.sort()
  end

  defp violations_of(file) do
    expected = expected_path(file)
    names = defined_modules(file)

    cond do
      names == [] -> []
      Enum.any?(names, &(Macro.underscore(&1) == expected)) -> strays(file, expected, names)
      true -> ["#{Path.relative_to(file, @umbrella)} defines no module named #{expected_module(expected)}"]
    end
  end

  defp strays(file, expected, names) do
    for name <- names, !named_under?(name, expected) do
      "#{Path.relative_to(file, @umbrella)} defines #{name}, " <>
        "which is not #{expected_module(expected)} and is not named under it"
    end
  end

  defp named_under?(name, expected) do
    path = Macro.underscore(name)
    path == expected or String.starts_with?(path, expected <> "/")
  end

  defp expected_path(file) do
    file
    |> Path.relative_to(root_of(file))
    |> Path.rootname()
    |> String.replace(".", "/")
  end

  defp expected_module(path) do
    path
    |> String.split("/")
    |> Enum.map_join(".", &Macro.camelize/1)
  end

  defp root_of(file) do
    parts = Path.split(file)
    depth = Enum.find_index(parts, &(&1 in ["lib", "support"]))

    parts
    |> Enum.take(depth + 1)
    |> Path.join()
  end

  defp defined_modules(file) do
    file
    |> File.read!()
    |> Code.string_to_quoted!()
    |> module_names([])
  end

  defp module_names({:defmodule, _meta, [{:__aliases__, _alias_meta, parts}, body]}, prefix) do
    name = prefix ++ parts
    [Enum.join(name, ".") | module_names(body, name)]
  end

  defp module_names({left, right}, prefix), do: module_names(left, prefix) ++ module_names(right, prefix)

  defp module_names({_form, _meta, arguments}, prefix) when is_list(arguments), do: module_names(arguments, prefix)

  defp module_names(list, prefix) when is_list(list), do: Enum.flat_map(list, &module_names(&1, prefix))

  defp module_names(_other, _prefix), do: []

  defp place_files(place) do
    @umbrella
    |> Path.join("apps/*/lib/**/#{place}/**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp place_modules(place) do
    MapSet.new(place_files(place), &expected_module(expected_path(&1)))
  end

  defp published?(file) do
    package =
      file
      |> Path.relative_to(@umbrella)
      |> Path.split()
      |> Enum.at(1)

    package in @published
  end

  defp effects_of(file) do
    aliases = aliases_of(file)

    file
    |> quoted(&calls/2)
    |> Enum.flat_map(&touched(&1, aliases))
    |> Enum.uniq()
    |> Enum.map(&"#{Path.relative_to(file, @umbrella)} calls #{&1}, which touches the world outside the call")
  end

  defp touched({form, arity}, _aliases), do: ["#{form}/#{arity}"]

  defp touched({target, function, arity}, aliases) do
    named = resolved(target, aliases)

    cond do
      {target, function} in @pure -> []
      named in @world -> ["#{named}.#{function}/#{arity}"]
      target in @erlang -> [":#{target}.#{function}/#{arity}"]
      function in @moments and named != nil -> ["#{named}.#{function}/#{arity}"]
      true -> []
    end
  end

  defp named_from(file, modules, place) do
    aliases = aliases_of(file)

    file
    |> quoted(&references/2)
    |> Enum.map(&resolved(&1, aliases))
    |> Enum.filter(&interior?(&1, modules))
    |> Enum.uniq()
    |> Enum.map(&"#{Path.relative_to(file, @umbrella)} names #{&1}, which is a module in #{place}/")
  end

  defp interior?(nil, _modules), do: false

  defp interior?(named, modules) do
    Enum.any?(modules, &(named == &1 or String.starts_with?(named, &1 <> ".")))
  end

  defp undocumented(file) do
    for {name, body} <- modules_of(file), !hidden?(body) do
      "#{Path.relative_to(file, @umbrella)} defines #{name} without @moduledoc false, " <>
        "and no interior place of a published package is public"
    end
  end

  defp hidden?(body) do
    body
    |> statements()
    |> Enum.any?(&match?({:@, _meta, [{:moduledoc, _doc_meta, [false]}]}, &1))
  end

  defp statements({:__block__, _meta, statements}), do: statements
  defp statements(other), do: [other]

  # Each module the file defines with the body it defines it with, the outer
  # module first.
  defp modules_of(file) do
    file
    |> quoted(&module_bodies/2)
    |> Enum.map(fn {parts, body} -> {Enum.map_join(parts, ".", &to_string/1), body} end)
  end

  defp module_bodies({:defmodule, _meta, [{:__aliases__, _alias_meta, parts}, [do: body]]}, found) do
    [{parts, body} | found]
  end

  defp module_bodies(_other, found), do: found

  # Every remote call the file makes, as the module named, the function, and
  # the arity.
  defp calls({{:., _meta, [target, function]}, _call_meta, arguments}, found)
       when is_atom(function) and is_list(arguments) do
    [{target, function, length(arguments)} | found]
  end

  defp calls({form, _meta, arguments}, found) when form in @forms and is_list(arguments) do
    [{form, length(arguments)} | found]
  end

  defp calls(_other, found), do: found

  defp references({:__aliases__, _meta, parts} = reference, found) do
    if Enum.all?(parts, &is_atom/1), do: [reference | found], else: found
  end

  defp references(_other, found), do: found

  defp resolved({:__aliases__, _meta, parts}, aliases) do
    case Enum.map(parts, &to_string/1) do
      [head | rest] -> Enum.join([Map.get(aliases, head, head) | rest], ".")
      [] -> nil
    end
  end

  defp resolved(_target, _aliases), do: nil

  # What each name in the file stands for: the last segment of an alias, or
  # the name `as:` gave it, against the module it names.
  defp aliases_of(file) do
    file
    |> quoted(&aliased/2)
    |> Map.new()
  end

  defp aliased({:alias, _meta, [{:__aliases__, _alias_meta, parts}]}, found), do: [named(parts) | found]

  defp aliased({:alias, _meta, [{:__aliases__, _alias_meta, parts}, [as: {:__aliases__, _as_meta, [as]}]]}, found) do
    [{to_string(as), Enum.map_join(parts, ".", &to_string/1)} | found]
  end

  defp aliased(
         {:alias, _meta, [{{:., _dot_meta, [{:__aliases__, _prefix_meta, prefix}, :{}]}, _brace_meta, each}]},
         found
       ) do
    Enum.map(each, fn {:__aliases__, _each_meta, parts} -> named(prefix ++ parts) end) ++ found
  end

  defp aliased(_other, found), do: found

  defp named(parts) do
    {to_string(List.last(parts)), Enum.map_join(parts, ".", &to_string/1)}
  end

  defp quoted(file, gather) do
    {_tree, found} =
      file
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], &{&1, gather.(&1, &2)})

    Enum.reverse(found)
  end
end
