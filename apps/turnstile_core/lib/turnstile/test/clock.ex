defmodule Turnstile.Test.Clock do
  @moduledoc """
  The `Mox` mock of `Turnstile.Clock` the conformance templates stub, and
  the one call that defines it. A suite defines it once, from
  `test_helper.exs` or from whatever raises the suite's database, and every
  test module then stubs `now/0` on it; defining it per test would race
  between modules that run at the same time.
  """

  @mock __MODULE__.Mock

  @doc "Define the mock, once per virtual machine. Safe to call twice."
  @spec define_mock() :: module()
  def define_mock do
    if !Code.ensure_loaded?(@mock), do: Mox.defmock(@mock, for: Turnstile.Clock)
    @mock
  end

  @doc "The mock module, whether or not it is defined yet."
  @spec mock() :: module()
  def mock, do: @mock
end
