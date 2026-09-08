defmodule Turnstile.Edge do
  @moduledoc """
  The conversions every struct with an edge shares. `to_map/1` on a struct
  produces a map of plain values: atoms as strings, modules by name, object
  references as maps, times in ISO 8601; `from_map/1` reads that map back,
  with atom or string keys, and answers `{:error, %Turnstile.Error.Invalid{}}`
  on anything else.
  """

  alias Turnstile.Error

  @type result(value) :: {:ok, value} | {:error, Error.Invalid.t()}

  @typedoc """
  How one field converts: `:string` and `:integer` refuse `nil`, `{:string, :nil_ok}`
  and `{:integer, :nil_ok}` keep it, `:atom`, `:module`, `:ref` and `:time` keep
  `nil`, `{:in, atoms}` is an atom from a fixed list, `{:struct, module}` is
  that module's struct or a map its `from_map/1` reads, and `:any` is kept as is.
  """
  @type field_spec ::
          :string
          | :integer
          | :atom
          | :module
          | :ref
          | :time
          | :any
          | {:string, :nil_ok}
          | {:integer, :nil_ok}
          | {:in, [atom()]}
          | {:struct, module()}

  @doc "The value under `key`, given as an atom, or under its string form."
  @spec fetch(map(), atom()) :: {:ok, term()} | :error
  def fetch(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, Atom.to_string(key))
    end
  end

  @doc "An atom as its string, `nil` kept."
  @spec atom_out(atom() | nil) :: String.t() | nil
  def atom_out(nil), do: nil
  def atom_out(atom) when is_atom(atom), do: Atom.to_string(atom)

  @doc "A string back to an atom that already exists, or the atom itself."
  @spec atom_in(term(), atom()) :: result(atom() | nil)
  def atom_in(nil, _what), do: {:ok, nil}
  def atom_in(atom, _what) when is_atom(atom), do: {:ok, atom}

  def atom_in(string, what) when is_binary(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> {:error, invalid(what, "unknown atom #{inspect(string)}")}
  end

  def atom_in(other, what), do: {:error, invalid(what, "expected an atom or a string, got: #{inspect(other)}")}

  @doc "A module as `inspect/1` names it."
  @spec module_out(module() | nil) :: String.t() | nil
  def module_out(nil), do: nil
  def module_out(module) when is_atom(module), do: inspect(module)

  @doc "A module name back to the module, which must be loaded."
  @spec module_in(term(), atom()) :: result(module() | nil)
  def module_in(nil, _what), do: {:ok, nil}
  def module_in(module, _what) when is_atom(module), do: {:ok, module}
  def module_in("Elixir." <> _rest = name, what), do: atom_in(name, what)
  def module_in(name, what) when is_binary(name), do: atom_in("Elixir." <> name, what)
  def module_in(other, what), do: {:error, invalid(what, "expected a module name, got: #{inspect(other)}")}

  @doc "A reference `{type, id}` as a map."
  @spec ref_out({atom(), term()} | nil) :: map() | nil
  def ref_out(nil), do: nil
  def ref_out({type, id}) when is_atom(type), do: %{type: atom_out(type), id: id}

  @doc "A reference map back to `{type, id}`."
  @spec ref_in(term(), atom()) :: result({atom(), term()} | nil)
  def ref_in(nil, _what), do: {:ok, nil}
  def ref_in({type, id}, _what) when is_atom(type), do: {:ok, {type, id}}

  def ref_in(map, what) when is_map(map) do
    with {:ok, type} <- fetch(map, :type),
         {:ok, id} <- fetch(map, :id),
         {:ok, type} <- atom_in(type, what) do
      {:ok, {type, id}}
    else
      :error -> {:error, invalid(what, "a reference needs type and id, got: #{inspect(map)}")}
      {:error, error} -> {:error, error}
    end
  end

  def ref_in(other, what), do: {:error, invalid(what, "expected a reference, got: #{inspect(other)}")}

  @doc "A time in ISO 8601."
  @spec time_out(DateTime.t() | nil) :: String.t() | nil
  def time_out(nil), do: nil
  def time_out(%DateTime{} = time), do: DateTime.to_iso8601(time)

  @doc "A time back from ISO 8601."
  @spec time_in(term(), atom()) :: result(DateTime.t() | nil)
  def time_in(nil, _what), do: {:ok, nil}
  def time_in(%DateTime{} = time, _what), do: {:ok, time}

  def time_in(string, what) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, time, _offset} -> {:ok, time}
      {:error, reason} -> {:error, invalid(what, "bad time #{inspect(string)}: #{reason}")}
    end
  end

  def time_in(other, what), do: {:error, invalid(what, "expected a time, got: #{inspect(other)}")}

  @doc "A string, or `nil` when allowed."
  @spec string_in(term(), atom(), boolean()) :: result(String.t() | nil)
  def string_in(nil, _what, true), do: {:ok, nil}
  def string_in(string, _what, _nil_ok) when is_binary(string), do: {:ok, string}
  def string_in(other, what, _nil_ok), do: {:error, invalid(what, "expected a string, got: #{inspect(other)}")}

  @doc "An integer, or `nil` when allowed."
  @spec integer_in(term(), atom(), boolean()) :: result(integer() | nil)
  def integer_in(nil, _what, true), do: {:ok, nil}
  def integer_in(integer, _what, _nil_ok) when is_integer(integer), do: {:ok, integer}
  def integer_in(other, what, _nil_ok), do: {:error, invalid(what, "expected an integer, got: #{inspect(other)}")}

  @doc "Every key of `keys` fetched from `map`, in order, or the first missing one named."
  @spec fetch_all(map(), [atom()], atom()) :: result([term()])
  def fetch_all(map, keys, what) when is_map(map) and is_list(keys) do
    fetched =
      Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, values} ->
        case fetch(map, key) do
          {:ok, value} -> {:cont, {:ok, [value | values]}}
          :error -> {:halt, {:error, invalid(what, "missing #{key}")}}
        end
      end)

    case fetched do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Every field of `spec` read from `map` and converted, in order, as a keyword
  list, or the first missing or unconvertible field's error. Fields named in
  `optional` may be absent and read as `nil`.
  """
  @spec convert(map(), [{atom(), field_spec()}], atom(), [atom()]) :: result(keyword())
  def convert(map, spec, what, optional \\ []) when is_map(map) and is_list(spec) do
    converted =
      Enum.reduce_while(spec, {:ok, []}, fn {field, kind}, {:ok, fields} ->
        case field_in(map, field, kind, what, optional) do
          {:ok, value} -> {:cont, {:ok, [{field, value} | fields]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    case converted do
      {:ok, fields} -> {:ok, Enum.reverse(fields)}
      {:error, error} -> {:error, error}
    end
  end

  @doc "One value converted as `spec` says."
  @spec value_in(term(), field_spec(), atom()) :: result(term())
  def value_in(value, :string, what), do: string_in(value, what, false)
  def value_in(value, {:string, :nil_ok}, what), do: string_in(value, what, true)
  def value_in(value, :integer, what), do: integer_in(value, what, false)
  def value_in(value, {:integer, :nil_ok}, what), do: integer_in(value, what, true)
  def value_in(value, :atom, what), do: atom_in(value, what)
  def value_in(value, :module, what), do: module_in(value, what)
  def value_in(value, :ref, what), do: ref_in(value, what)
  def value_in(value, :time, what), do: time_in(value, what)
  def value_in(value, :any, _what), do: {:ok, value}

  def value_in(value, {:in, atoms}, what) do
    with {:ok, atom} <- atom_in(value, what) do
      if atom in atoms do
        {:ok, atom}
      else
        {:error, invalid(what, "expected one of #{inspect(atoms)}, got: #{inspect(atom)}")}
      end
    end
  end

  def value_in(%{__struct__: module} = value, {:struct, module}, _what), do: {:ok, value}
  def value_in(value, {:struct, module}, _what) when is_map(value), do: module.from_map(value)

  def value_in(other, {:struct, module}, what),
    do: {:error, invalid(what, "expected #{inspect(module)}, got: #{inspect(other)}")}

  @doc "The invalid error for an edge."
  @spec invalid(atom(), String.t()) :: Error.Invalid.t()
  def invalid(what, detail) when is_atom(what) and is_binary(detail), do: %Error.Invalid{what: what, detail: detail}

  defp field_in(map, field, kind, what, optional) do
    case fetch(map, field) do
      {:ok, value} -> value_in(value, kind, what)
      :error -> absent_in(field, kind, what, optional)
    end
  end

  defp absent_in(field, kind, what, optional) do
    if field in optional do
      value_in(nil, kind, what)
    else
      {:error, invalid(what, "missing #{field}")}
    end
  end
end
