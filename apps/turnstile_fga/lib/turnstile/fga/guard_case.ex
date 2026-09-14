defmodule Turnstile.Fga.GuardCase do
  @moduledoc """
  The case template a guard is proved by. `use Turnstile.Fga.GuardCase,
  guard: MyApp.Guard, operations: [:read, :edit], admitting: [%{...}],
  refusing: [%{...}]` defines a test module that holds the guard to what
  every callback relies on when it consults one.

  A guard is asked before any question goes to the server, so a guard that
  raises is an outage of the whole adapter and a guard that answers anything
  other than a boolean is a callback with no answer to give. The template
  asks it about every operation the application named, under the
  environments the application says it admits, the environments it says it
  refuses, an environment stating nothing, and an operation it never
  declared. All of those have to answer, and the last two have to answer
  `false`: a guard that cannot tell is a guard that does not admit.

  What a refusal then does is the adapter's rather than the guard's, and
  `Turnstile.Fga`'s own conformance holds that: the denial names the guard
  as the rule, and the store is not asked.

  Options:

  - `guard:` the `Turnstile.Fga.Guard` module, required.
  - `operations:` the operations the application asks about, required.
  - `admitting:` environments the guard admits every one of those
    operations under, required, at least one.
  - `refusing:` environments the guard refuses every one of those
    operations under, default `[]`.
  - `async:` default `true`.
  """

  import ExUnit.Assertions

  @nothing :turnstile_fga_guard_case_undeclared_operation

  @doc false
  defmacro __using__(opts) do
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)

    config = %{
      guard: Keyword.fetch!(opts, :guard),
      operations: Keyword.fetch!(opts, :operations),
      admitting: Keyword.fetch!(opts, :admitting),
      refusing: Keyword.get(opts, :refusing, [])
    }

    [preamble(config, Keyword.get(opts, :async, true)), totality(), answers()]
  end

  @doc false
  @spec answers_a_boolean(map()) :: true
  def answers_a_boolean(config) do
    answers =
      for operation <- operations(config), environment <- environments(config), do: ask(config, operation, environment)

    assert(answers != [])
    assert(Enum.all?(answers, &is_boolean/1))
  end

  @doc false
  @spec answers_the_same_twice(map()) :: true
  def answers_the_same_twice(config) do
    Enum.each(operations(config), fn operation ->
      Enum.each(environments(config), fn environment ->
        assert(ask(config, operation, environment) == ask(config, operation, environment))
      end)
    end)
  end

  @doc false
  @spec admits_what_it_says(map()) :: true
  def admits_what_it_says(config) do
    assert(config.admitting != [], "a guard with no environment it admits admits nothing, and denies every call")

    Enum.each(config.admitting, fn environment ->
      Enum.each(config.operations, fn operation ->
        assert(ask(config, operation, environment), "#{inspect(operation)} under #{inspect(environment)}")
      end)
    end)
  end

  @doc false
  @spec refuses_what_it_says(map()) :: true
  def refuses_what_it_says(config) do
    Enum.each(config.refusing, fn environment ->
      Enum.each(config.operations, fn operation ->
        refute(ask(config, operation, environment), "#{inspect(operation)} under #{inspect(environment)}")
      end)
    end)
  end

  @doc false
  @spec refuses_an_undeclared_operation(map()) :: true
  def refuses_an_undeclared_operation(config) do
    Enum.each(environments(config), &refute(ask(config, @nothing, &1)))
  end

  defp ask(config, operation, environment), do: config.guard.admits?(operation, environment)

  defp operations(config), do: [@nothing | config.operations]

  defp environments(config), do: [%{} | config.admitting] ++ config.refusing

  defp preamble(config, async) do
    quote do
      use ExUnit.Case, async: unquote(async)

      @guard_case unquote(Macro.escape(config))
    end
  end

  defp totality do
    quote do
      test "every operation under every environment answers a boolean" do
        unquote(__MODULE__).answers_a_boolean(@guard_case)
      end

      test "a guard asked twice about the same call answers the same" do
        unquote(__MODULE__).answers_the_same_twice(@guard_case)
      end
    end
  end

  defp answers do
    quote do
      test "an environment the application says is admitted admits every operation" do
        unquote(__MODULE__).admits_what_it_says(@guard_case)
      end

      test "an environment the application says is refused refuses every operation" do
        unquote(__MODULE__).refuses_what_it_says(@guard_case)
      end

      test "an operation the application never declared is not admitted" do
        unquote(__MODULE__).refuses_an_undeclared_operation(@guard_case)
      end
    end
  end
end
