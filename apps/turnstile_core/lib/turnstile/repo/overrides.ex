defmodule Turnstile.Repo.Overrides do
  @moduledoc false
  # Generates, at the repo's `@before_compile`, the override of every
  # `Turnstile.Repo.Surface` function the repo defines. Each override calls
  # the seam with the arguments and a function that runs Ecto's own
  # definition with the options the seam settled.

  alias Turnstile.Repo.Seam

  @doc false
  defmacro __before_compile__(env) do
    generate(env.module, Module.get_attribute(env.module, :turnstile_surface))
  end

  @doc """
  The quoted overrides for the functions of `surface` that `module` defines.
  The surface arrives from the repo's own `@turnstile_surface`, which
  `use Turnstile.Repo` sets, so this file references no other module and a
  repo that uses it recompiles for no change but its own.
  """
  @spec generate(module(), [{atom(), non_neg_integer(), atom()}]) :: Macro.t()
  def generate(module, surface) when is_atom(module) and is_list(surface) do
    overrides =
      module
      |> defined(surface)
      |> Enum.flat_map(fn {{name, bucket}, arities} -> override(name, bucket, arities) end)

    quote do
      (unquote_splicing(overrides))
    end
  end

  # The surface grouped by name and bucket, kept where `module` defines every arity.
  defp defined(module, surface) do
    surface
    |> Enum.group_by(fn {name, _arity, bucket} -> {name, bucket} end, fn {_name, arity, _bucket} -> arity end)
    |> Enum.sort()
    |> Enum.filter(fn {{name, _bucket}, arities} -> Enum.all?(arities, &Module.defines?(module, {name, &1})) end)
    |> Enum.map(fn {key, arities} -> {key, Enum.sort(arities)} end)
  end

  defp override(:prepare_query, :plumbing, [3]) do
    [
      quote do
        defoverridable prepare_query: 3

        def prepare_query(operation, query, opts) do
          {query, opts} = Seam.prepare(__MODULE__, operation, query, opts)
          super(operation, query, opts)
        end
      end
    ]
  end

  defp override(_name, :plumbing, _arities), do: []

  defp override(:aggregate, :query, [2, 3, 4]) do
    [
      quote do
        defoverridable aggregate: 2, aggregate: 3, aggregate: 4
        def aggregate(queryable, aggregate), do: aggregate(queryable, aggregate, [])
        def aggregate(queryable, aggregate, field) when is_atom(field), do: aggregate(queryable, aggregate, field, [])
      end,
      aggregate_three(),
      aggregate_four()
    ]
  end

  defp override(name, bucket, arities) do
    max = Enum.max(arities)
    args = Macro.generate_arguments(max - 1, __MODULE__)
    lowers = for arity <- arities, arity != max, do: lower(name, arity, args, max)

    [overridable(name, arities), full(name, bucket, args, max) | lowers]
  end

  defp overridable(name, arities) do
    quote do
      defoverridable unquote(Enum.map(arities, &{name, &1}))
    end
  end

  # `aggregate/3` is either `(queryable, aggregate, opts)` or `(queryable, aggregate, field)`.
  defp aggregate_three do
    quote do
      def aggregate(queryable, aggregate, opts) when is_list(opts) do
        Seam.query(__MODULE__, {:aggregate, 3}, queryable, opts, fn opts -> super(queryable, aggregate, opts) end)
      end
    end
  end

  defp aggregate_four do
    quote do
      def aggregate(queryable, aggregate, field, opts) do
        Seam.query(__MODULE__, {:aggregate, 4}, queryable, opts, fn opts ->
          super(queryable, aggregate, field, opts)
        end)
      end
    end
  end

  # A lower arity fills the missing arguments with `[]` and calls the full one.
  defp lower(name, arity, args, max) do
    given = Enum.take(args, arity)
    filled = given ++ List.duplicate([], max - arity)

    quote do
      def unquote(name)(unquote_splicing(given)), do: unquote(name)(unquote_splicing(filled))
    end
  end

  defp full(name, bucket, args, max) do
    opts = Macro.var(:opts, __MODULE__)
    call = Macro.escape({name, max})
    continue = quote do: fn unquote(opts) -> super(unquote_splicing(args), unquote(opts)) end

    quote do
      def unquote(name)(unquote_splicing(args), unquote(opts)) do
        unquote(seam(name, bucket, call, args, opts, continue))
      end
    end
  end

  defp seam(:update_all, :query, call, [queryable, updates], opts, continue) do
    quote do
      Seam.bulk(
        __MODULE__,
        unquote(call),
        unquote(queryable),
        unquote(updates),
        unquote(opts),
        unquote(continue)
      )
    end
  end

  defp seam(:delete_all, :query, call, [queryable], opts, continue) do
    quote do
      Seam.bulk(__MODULE__, unquote(call), unquote(queryable), nil, unquote(opts), unquote(continue))
    end
  end

  defp seam(_name, :query, call, [target | _rest], opts, continue) do
    quote do
      Seam.query(__MODULE__, unquote(call), unquote(target), unquote(opts), unquote(continue))
    end
  end

  defp seam(:insert_all, :write, call, [source, entries], opts, continue) do
    quote do
      Seam.write_all(
        __MODULE__,
        unquote(call),
        unquote(source),
        unquote(entries),
        unquote(opts),
        unquote(continue)
      )
    end
  end

  defp seam(_name, :write, call, [changeset], opts, continue) do
    quote do
      Seam.write(__MODULE__, unquote(call), unquote(changeset), unquote(opts), unquote(continue))
    end
  end

  defp seam(_name, :raw, call, _args, opts, continue) do
    quote do
      Seam.raw(__MODULE__, unquote(call), unquote(opts), unquote(continue))
    end
  end
end
