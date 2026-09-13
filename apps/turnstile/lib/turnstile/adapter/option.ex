defmodule Turnstile.Adapter.Option do
  @moduledoc false
  # The `turnstile:` option resolved against the process the call runs in:
  # the repo's role, the caller the stack names, and the ambient mediation a
  # nested call reuses. What the option means is
  # `Turnstile.Core.Mediation`'s to say; this module reads what only the
  # running process can tell, and hands the answer back as that struct.

  alias Turnstile.Adapter.Caller
  alias Turnstile.Core.Mediation
  alias Turnstile.Decision

  @doc """
  Resolve the option in `opts` for a call on `repo` whose root source is
  `root`. Returns the mediation, empty when no option was given, and the
  options with the struct in the option's place.
  """
  @spec resolve(module(), Mediation.call(), Mediation.root(), keyword()) :: {Mediation.t(), keyword()}
  def resolve(repo, {name, arity} = call, root, opts) when is_atom(repo) and is_atom(name) and is_list(opts) do
    if repo.__turnstile__(:role) == :owner do
      put(Mediation.library(call, root, repo), opts)
    else
      given(repo, {name, arity}, root, opts, Keyword.fetch(opts, :turnstile))
    end
  end

  @doc """
  Run `fun` with `mediation` as the ambient mediation of the process: the
  one a call with no option inside it reuses. Ecto hands a nested
  association write only the parent's `timeout`, `log`, `telemetry_event`,
  `prefix`, and `allow_stale` options, so the parent's mediation reaches
  the child this way, for the parent's own duration.
  """
  @spec with_ambient(Mediation.t(), (-> result)) :: result when result: term()
  def with_ambient(%Mediation{} = mediation, fun) when is_function(fun, 0) do
    previous = Process.put(__MODULE__, mediation)

    try do
      fun.()
    after
      restore(previous)
    end
  end

  defp given(_repo, call, _root, opts, :error), do: ambient(call, opts)
  defp given(_repo, call, _root, opts, {:ok, %Mediation{} = nested}), do: put(%{nested | call: call}, opts)
  defp given(repo, call, root, opts, {:ok, value}), do: put(settled(repo, call, root, Mediation.validate!(value)), opts)

  defp ambient(call, opts) do
    case Process.get(__MODULE__) do
      %Mediation{} = outer -> put(%{outer | call: call}, opts)
      nil -> put(Mediation.empty(call), opts)
    end
  end

  defp put(%Mediation{} = mediation, opts), do: {mediation, Keyword.put(opts, :turnstile, mediation)}

  defp restore(nil), do: Process.delete(__MODULE__)
  defp restore(%Mediation{} = previous), do: Process.put(__MODULE__, previous)

  defp settled(_repo, call, root, %Decision{} = decision), do: Mediation.decided(call, root, decision)

  defp settled(repo, call, root, {:exempt, :library}) do
    caller = Caller.module(repo)

    if Caller.library?(caller) do
      Mediation.library(call, root, caller)
    else
      {name, arity} = call

      raise Mediation.unmediated(
              function: name,
              arity: arity,
              schema: schema_of(root),
              caller: caller,
              detail: "{:exempt, :library} is accepted only from a Turnstile.* caller"
            )
    end
  end

  defp settled(repo, call, root, {:exempt, reason}), do: Mediation.declared(call, root, Caller.module(repo), reason)

  defp schema_of(root) when is_atom(root), do: root
  defp schema_of(_root), do: nil
end
