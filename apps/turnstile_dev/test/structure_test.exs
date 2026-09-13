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

  The test reads the syntax tree rather than the compiled modules, so it
  starts nothing and depends on nothing it reads.

  `@exceptions` names each file that cannot follow the rule, with its
  reason. `PLAN.md` §2 states the rule and the two dependency gates that
  shape it.
  """

  use ExUnit.Case, async: true

  @umbrella Path.expand("../../..", __DIR__)

  @exceptions %{
    "apps/example/lib/example/document.ex" =>
      "a document, its markings, its portions, and its proposals refer to one another"
  }

  test "a file's path names a module it defines, and its other modules are named under that one" do
    violations =
      @umbrella
      |> source_files()
      |> Enum.reject(&is_map_key(@exceptions, Path.relative_to(&1, @umbrella)))
      |> Enum.flat_map(&violations_of/1)

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
end
