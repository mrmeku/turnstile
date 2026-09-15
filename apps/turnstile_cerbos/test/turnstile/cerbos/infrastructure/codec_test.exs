defmodule Turnstile.Cerbos.CodecTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Turnstile.Cerbos.Infrastructure.Codec

  @scalars [:string, :integer, :float, :boolean, :date, :time, :naive_datetime, :utc_datetime]

  property "a value the adapter sends is the value a plan compiled from the same policy reads back" do
    check all({type, value} <- declared()) do
      encoded = Codec.encode(value)

      assert Ecto.Type.cast(type, encoded) == {:ok, value}
      assert JSON.decode!(JSON.encode!(%{"attr" => encoded})) == %{"attr" => encoded}
    end
  end

  property "a moment is cut to the second, so a policy and a plan compare the same precision" do
    check all(moment <- utc_datetime(), microsecond <- integer(1..999_999)) do
      finer = %{moment | microsecond: {microsecond, 6}}

      assert Codec.moment(finer) == DateTime.to_iso8601(moment)
      assert Ecto.Type.cast(:utc_datetime, Codec.moment(finer)) == {:ok, moment}
    end
  end

  property "a value of any other shape crosses as the text it is worth" do
    check all(atom <- map(string(:alphanumeric, min_length: 1), &String.to_atom/1)) do
      assert Codec.encode(atom) == Atom.to_string(atom)
      assert Ecto.Type.cast(:string, Codec.encode(atom)) == {:ok, Atom.to_string(atom)}
    end
  end

  test "nothing in the column goes as null, which every type reads back as nothing" do
    for type <- @scalars do
      assert Codec.encode(nil) == nil
      assert Ecto.Type.cast(type, Codec.encode(nil)) == {:ok, nil}
      assert Ecto.Type.cast({:array, type}, Codec.encode([])) == {:ok, []}
    end
  end

  test "a boolean crosses as itself, since JSON carries one" do
    assert Codec.encode(true) == true
    assert Codec.encode(false) == false
  end

  # A declared attribute's type and a value of it, as a column holds the
  # value and a plan compiled from the policy casts it back.
  defp declared do
    one_of([scalar(), many()])
  end

  defp scalar do
    bind(member_of(@scalars), fn type -> map(values(type), &{type, &1}) end)
  end

  # A subquery answers a list, and an array column holds one, which is what
  # a rule over a subject's reach compares against.
  defp many do
    bind(member_of(@scalars), fn type ->
      map(list_of(values(type), max_length: 5), &{{:array, type}, &1})
    end)
  end

  defp values(:string), do: string(:printable)
  defp values(:integer), do: integer()
  defp values(:float), do: float()
  defp values(:boolean), do: boolean()
  defp values(:date), do: date()
  defp values(:time), do: time()
  defp values(:naive_datetime), do: naive_datetime()
  defp values(:utc_datetime), do: utc_datetime()

  defp time, do: map(integer(0..86_399), &Time.from_seconds_after_midnight/1)

  defp naive_datetime, do: map(tuple({date(), time()}), fn {day, clock} -> NaiveDateTime.new!(day, clock) end)

  defp utc_datetime, do: map(naive_datetime(), &DateTime.from_naive!(&1, "Etc/UTC"))
end
