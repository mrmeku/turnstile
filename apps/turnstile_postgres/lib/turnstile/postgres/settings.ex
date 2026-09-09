defmodule Turnstile.Postgres.Settings do
  @moduledoc """
  The session settings a call runs under. Four are always set:
  `turnstile.subject_id`, `turnstile.subject_kind`, `turnstile.operation`,
  and `turnstile.now`. Beyond those, every fact the caller supplied in the
  environment is set under its own name, so an application whose policies
  read `current_setting('turnstile.reauthenticated_at', true)` supplies
  `reauthenticated_at` as a fact and this package never learns the name.

  Every value is text. A value the caller did not supply is the empty
  string, and a name the caller never supplied is unset, which
  `current_setting(name, true)` answers as `NULL`; neither compares equal
  to anything a policy grants on, so an absent fact denies.

  `statement/1` renders the settings as one `SELECT` over
  `set_config(name, value, true)`, which is one statement, one round trip,
  and one query in the shape counts. `hash/1` is the SHA-256 a scope
  decision carries as its rule text, because under row-level security the
  settings are what the database enforced.
  """

  alias Turnstile.Environment
  alias Turnstile.Subject

  @prefix "turnstile."

  @enforce_keys [:pairs]
  defstruct @enforce_keys

  @typedoc "The setting names and their text values, in the order they are set and hashed."
  @type t :: %__MODULE__{pairs: [{String.t(), String.t()}]}

  @doc """
  The settings for a subject, an operation, and either the environment of
  the call or, where only a decision is at hand, the time it was made. The
  second form carries no supplied fact, so a policy that reads one denies.
  """
  @spec of(Subject.t(), atom(), Environment.t() | DateTime.t()) :: t()
  def of(%Subject{} = subject, operation, %Environment{} = environment) when is_atom(operation) do
    fixed = [
      {"subject_id", subject.id},
      {"subject_kind", subject.kind},
      {"operation", operation},
      {"now", environment.now}
    ]

    %__MODULE__{pairs: Enum.map(fixed ++ supplied(environment), &pair/1)}
  end

  def of(%Subject{} = subject, operation, %DateTime{} = at) when is_atom(operation) do
    of(subject, operation, %Environment{now: at})
  end

  @doc """
  The same names with no values, which is what a call puts back when no
  call around it holds the connection. A name at the empty string is what a
  policy reads for "no operation in force"; unsetting a name is not
  available to a statement.
  """
  @spec cleared(t()) :: t()
  def cleared(%__MODULE__{pairs: pairs}) do
    %__MODULE__{pairs: Enum.map(pairs, fn {name, _value} -> {name, ""} end)}
  end

  @doc """
  The names a call set, put back to what the call around it holds: a name
  the outer call set takes its value again, and a name only the inner call
  set goes to the empty string. Each name appears once, so the order the
  database evaluates the calls in does not matter.
  """
  @spec restored(t(), t()) :: t()
  def restored(%__MODULE__{} = settings, %__MODULE__{pairs: outer}) do
    held = MapSet.new(outer, fn {name, _value} -> name end)
    %__MODULE__{pairs: pairs} = cleared(settings)
    %__MODULE__{pairs: Enum.reject(pairs, fn {name, _value} -> name in held end) ++ outer}
  end

  @doc "The one statement that sets them all, with its parameters."
  @spec statement(t()) :: {String.t(), [String.t()]}
  def statement(%__MODULE__{pairs: pairs}) do
    calls =
      pairs
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {_pair, index} -> "set_config($#{2 * index + 1}, $#{2 * index + 2}, true)" end)

    {"SELECT " <> calls, Enum.flat_map(pairs, fn {name, value} -> [name, value] end)}
  end

  @doc "The SHA-256 of the settings, lowercase hexadecimal."
  @spec hash(t()) :: String.t()
  def hash(%__MODULE__{pairs: pairs}) do
    text = Enum.map_join(pairs, "\n", fn {name, value} -> name <> "=" <> value end)
    Base.encode16(:crypto.hash(:sha256, text), case: :lower)
  end

  defp supplied(%Environment{facts: facts}) do
    facts
    |> Enum.sort_by(fn {name, _value} -> name end)
    |> Enum.map(fn {name, value} -> {to_string(name), value} end)
  end

  defp pair({name, value}), do: {@prefix <> to_string(name), render(value)}

  defp render(nil), do: ""
  defp render(value) when is_binary(value), do: value
  defp render(value) when is_atom(value), do: Atom.to_string(value)
  defp render(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp render(value) when is_number(value), do: to_string(value)
  defp render(value) when is_list(value), do: Enum.map_join(value, ",", &render/1)
  defp render(value), do: inspect(value)
end
