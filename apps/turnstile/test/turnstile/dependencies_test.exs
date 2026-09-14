defmodule Turnstile.DependenciesTest do
  use ExUnit.Case, async: true

  # The first of the two numbers the plan runs in CI. A dependency this
  # package carries is one an adopter installs and starts, so the count is
  # the promise the package makes about its own size, and a fifth one is a
  # decision rather than an accident.
  @runtime ~w[ecto nimble_options stream_data telemetry]a

  test "the runtime dependencies are the four the plan names, and no more" do
    assert Enum.sort(runtime(Mix.Project.config()[:deps])) == @runtime
  end

  # What a production build installs and starts: not a tool held to dev and
  # test, not one marked `runtime: false`, and not one an adopter may leave
  # out.
  defp runtime(deps) do
    for dep <- deps, options = options(dep), installed?(options), do: elem(dep, 0)
  end

  defp options({_name, options}) when is_list(options), do: options
  defp options({_name, _requirement}), do: []
  defp options({_name, _requirement, options}), do: options

  defp installed?(options) do
    only = Keyword.get(options, :only)

    (is_nil(only) or :prod in List.wrap(only)) and
      Keyword.get(options, :runtime, true) and
      not Keyword.get(options, :optional, false)
  end
end
