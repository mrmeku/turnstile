defmodule Turnstile.Conformance.AdapterCase do
  @moduledoc """
  The Tier 1 case template. `use Turnstile.Conformance.AdapterCase,
  adapter: Turnstile.Code, repo: Example.Repo` defines an async test module
  whose setup checks out the sandbox on the repo, inserts the test's counter
  row, and binds the adapter through the configuration override, so each
  adapter's conformance run is its own module and all of them run in one
  `mix test`. The port's invariants, as properties over generators the
  adapter's test module supplies, are defined here as the stages add them.
  """

  alias Turnstile.Test.Sandbox

  @doc false
  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    repo = Keyword.fetch!(opts, :repo)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

      @moduletag adapter: unquote(adapter)

      setup tags do
        :ok = Sandbox.setup(unquote(repo), tags)
        :ok = Turnstile.Test.with_config(adapter: unquote(adapter))
        {:ok, adapter: unquote(adapter)}
      end

      test "the adapter declares whether it requires a ledger and its scope cap", %{adapter: adapter} do
        assert is_boolean(adapter.requires_ledger())
        assert adapter.scope_cap() == :none or is_integer(adapter.scope_cap())
      end
    end
  end
end
