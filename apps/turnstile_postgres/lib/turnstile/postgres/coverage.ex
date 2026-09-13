defmodule Turnstile.Postgres.Coverage do
  @moduledoc """
  Declared-fact coverage for row-level security: every column the policies
  read is a declared fact. `check/1` reads the policy expressions from
  `pg_policy` and the columns they reference from `pg_depend`, which
  records one dependency per column an expression names, then asks the
  bound schemas whether each of those columns is declared.

  A column counts as declared when a `fact` declaration on its schema names
  it as the fact column, the subject, or the object, when a `relationship`
  declaration names it as the subject, the object, or an attribute, when it
  is the schema's primary key, or when it is the foreign key of a relation
  a bound schema carries, through the closure of what the carried schemas
  carry in turn.

  A policy that reads a column no declaration names fails with that
  column's name, because a decision that depended on it would rest on a
  fact no record of a change covers. A policy that reads a table no bound
  schema names fails as `{:table, name}`, for the same reason.
  """

  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Core.Declared

  @typedoc "An undeclared read: the schema and the column, or a table no bound schema names."
  @type finding :: {module(), String.t()} | {:table, String.t()}

  @doc "Ok, or the undeclared reads, sorted and without repeats."
  @spec check(Binding.t()) :: :ok | {:error, [finding()]}
  def check(%Binding{} = binding) do
    case undeclared(binding) do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @doc "`check/1`, raising with every finding named."
  @spec check!(Binding.t()) :: :ok
  def check!(%Binding{} = binding) do
    case check(binding) do
      :ok -> :ok
      {:error, findings} -> raise ArgumentError, "policies read undeclared columns: " <> Declared.describe(findings)
    end
  end

  @doc "Every undeclared read the bound tables' policies make."
  @spec undeclared(Binding.t()) :: [finding()]
  def undeclared(%Binding{} = binding) do
    %Catalog{columns: columns} = Catalog.read!(binding)
    Declared.findings(binding, columns)
  end
end
