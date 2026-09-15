defmodule Turnstile.IdTest do
  use ExUnit.Case, async: true

  alias Turnstile.Id

  test "ids are UUIDs in canonical form, fresh on every call" do
    id = Id.new()
    assert {:ok, ^id} = Ecto.UUID.cast(id)
    refute id == Id.new()
  end
end
