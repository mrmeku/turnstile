defmodule Turnstile.Ledger.Ecto.Value do
  @moduledoc """
  What a fact value becomes in a json column, and what comes back. A string,
  a number, a boolean, and nothing itself go in as they are. An atom, a
  time, a list, and a map of attributes carry a tag, so a role reads back as
  the atom `:editor` rather than the string that printed it. Every value
  sits under one key, `v`, because the column is a json object.

  A value of another shape, a struct the codec has no tag for, is a
  programmer's mistake in a fact declaration rather than bad input, so it
  raises.
  """

  alias Turnstile.Edge
  alias Turnstile.Error

  @what :fact_value

  @doc "A fact value as the column holds it."
  @spec dump(term()) :: map()
  def dump(value), do: %{"v" => out(value)}

  @doc "A column's value back to the term that was written."
  @spec load(term()) :: {:ok, term()} | {:error, Error.Invalid.t()}
  def load(nil), do: {:ok, nil}
  def load(%{"v" => value}), do: back(value)
  def load(other), do: {:error, Edge.invalid(@what, "expected a value under \"v\", got: #{inspect(other)}")}

  @doc "A reference as the column holds it, with the id tagged the way a value is."
  @spec ref_dump({atom(), term()} | nil) :: map() | nil
  def ref_dump(nil), do: nil
  def ref_dump({type, id}) when is_atom(type), do: %{"type" => Atom.to_string(type), "id" => out(id)}

  @doc "A column's reference back to `{type, id}`."
  @spec ref_load(term()) :: {:ok, {atom(), term()} | nil} | {:error, Error.Invalid.t()}
  def ref_load(nil), do: {:ok, nil}

  def ref_load(%{"type" => type, "id" => id}) do
    with {:ok, type} <- Edge.atom_in(type, @what),
         {:ok, id} <- back(id) do
      {:ok, {type, id}}
    end
  end

  def ref_load(other), do: {:error, Edge.invalid(@what, "expected a reference, got: #{inspect(other)}")}

  defp out(nil), do: nil
  defp out(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp out(%DateTime{} = value), do: %{"time" => DateTime.to_iso8601(value)}

  defp out(%module{}) do
    raise Error.Invalid,
      what: @what,
      detail:
        "no encoding for #{inspect(module)}; a fact value is a string, a number, a boolean, an atom, " <>
          "a time, a list, or a map of them"
  end

  defp out(value) when is_atom(value), do: %{"atom" => Atom.to_string(value)}
  defp out(value) when is_list(value), do: %{"list" => Enum.map(value, &out/1)}
  defp out(value) when is_map(value), do: %{"pairs" => Enum.map(value, fn {key, item} -> [out(key), out(item)] end)}

  defp back(nil), do: {:ok, nil}
  defp back(value) when is_binary(value) or is_number(value) or is_boolean(value), do: {:ok, value}
  defp back(%{"time" => value}), do: Edge.time_in(value, @what)
  defp back(%{"atom" => value}), do: Edge.atom_in(value, @what)
  defp back(%{"list" => values}) when is_list(values), do: all(values)

  defp back(%{"pairs" => pairs}) when is_list(pairs) do
    with {:ok, flat} <- all(Enum.concat(pairs)) do
      {:ok, pairs(flat)}
    end
  end

  defp back(other), do: {:error, Edge.invalid(@what, "no value in #{inspect(other)}")}

  defp pairs(flat) do
    flat
    |> Enum.chunk_every(2)
    |> Map.new(fn [key, item] -> {key, item} end)
  end

  defp all(values) do
    reduced =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, done} ->
        case back(value) do
          {:ok, value} -> {:cont, {:ok, [value | done]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    case reduced do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      {:error, error} -> {:error, error}
    end
  end
end
