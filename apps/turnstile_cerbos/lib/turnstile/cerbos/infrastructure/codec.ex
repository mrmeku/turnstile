defmodule Turnstile.Cerbos.Infrastructure.Codec do
  @moduledoc false
  # A value on its way to the sidecar. JSON carries numbers, strings,
  # booleans, and null; a value of any other shape crosses as text, so an
  # `Ecto.Enum` column reaches the sidecar as the string the column holds
  # and a date as its ISO 8601 form.
  #
  # The encoding is what a policy compares, and a plan compiled from that
  # same policy compares a column of the database against the value the
  # policy carries, which `Ecto.Type.cast/2` reads back into the column's
  # type. The two readings agree only where the encoding is one that cast
  # answers with the value that was encoded.
  #
  # A moment is cut to the second first, because a column holds
  # microseconds the text of a moment does not, and a comparison between the
  # two is a comparison of different precisions.

  @doc "The value as JSON carries it, with a moment cut to the second."
  @spec moment(term()) :: term()
  def moment(%DateTime{} = value), do: encode(DateTime.truncate(value, :second))
  def moment(value), do: encode(value)

  @doc "The value as JSON carries it."
  @spec encode(term()) :: term()
  def encode(nil), do: nil
  def encode(true), do: true
  def encode(false), do: false
  def encode(value) when is_atom(value), do: Atom.to_string(value)
  def encode(%Date{} = value), do: Date.to_iso8601(value)
  def encode(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def encode(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def encode(%Time{} = value), do: Time.to_iso8601(value)
  def encode(value) when is_list(value), do: Enum.map(value, &encode/1)
  def encode(value), do: value
end
