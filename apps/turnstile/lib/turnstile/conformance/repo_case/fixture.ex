defmodule Turnstile.Conformance.RepoCase.Fixture do
  @moduledoc false
  # The arguments `Turnstile.Conformance.RepoCase` sweeps each surface
  # function with, on the protected schema.

  alias Turnstile.Conformance.RepoCase.Protected

  @row %Protected{id: 1, parent_id: 2}

  @doc "Fixture arguments for a surface function."
  @spec args(atom(), non_neg_integer()) :: [term()]
  def args(:aggregate, 4), do: [Protected, :avg, :id, []]

  def args(name, arity) do
    name
    |> full()
    |> Enum.take(arity)
  end

  defp full(:aggregate), do: [Protected, :count, []]
  defp full(:preload), do: [@row, :parent, []]
  defp full(:reload), do: [@row, []]
  defp full(:reload!), do: [@row, []]
  defp full(:update_all), do: [Protected, [set: [name: "renamed"]], []]
  defp full(:insert_all), do: [Protected, [%{name: "new"}], []]
  defp full(name) when name in [:get, :get!], do: [Protected, 1, []]
  defp full(name) when name in [:get_by, :get_by!, :all_by], do: [Protected, [id: 1], []]
  defp full(name) when name in [:insert, :insert!], do: [%Protected{name: "new"}, []]
  defp full(name) when name in [:update, :update!], do: [Ecto.Changeset.change(@row, name: "renamed"), []]
  defp full(name) when name in [:insert_or_update, :insert_or_update!], do: [Ecto.Changeset.change(@row), []]
  defp full(name) when name in [:delete, :delete!], do: [@row, []]
  defp full(name) when name in [:query, :query!, :query_many, :query_many!], do: ["SELECT 1", [], []]
  defp full(_name), do: [Protected, []]
end
