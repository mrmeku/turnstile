defmodule Turnstile.Conformance.LedgerCase do
  @moduledoc """
  The conformance case for `Turnstile.Ledger`, so every ledger, in this
  repository or outside it, proves the same contract. `use
  Turnstile.Conformance.LedgerCase, ledger: :memory` defines a test module
  whose cases are the behaviour's laws: an empty ledger has head 0 and reads
  nothing; an append stamps consecutive positions from the head and moves
  it; a read from a position returns what lies above it, in order, up to the
  limit; an appended event reads back as it was appended, whatever the
  storage does to it on the way; and the options schema accepts the options
  the case was given and refuses an empty list. A module that exports
  `transaction/2` gets one more case: the function's value comes back and
  what it appended inside is readable after it.

  Options:

  - `ledger:` `:memory`, a `Turnstile.Ledger.Memory` started per test, or
    `{module, options}`, the tuple a configuration carries.
  - `repo:` a sandboxed application-role repo, checked out for each test,
    for a ledger whose events live in a database. Omit it for a ledger that
    keeps them in a process.
  - `adapter:` the adapter the configuration override names, since a
    configuration needs one even where no decision is asked for; default
    `Turnstile.Adapter.Fake`.
  - `async:` default `true`.
  """

  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Memory
  alias Turnstile.Test.Clock.Mock
  alias Turnstile.Test.Sandbox

  @doc false
  defmacro __using__(opts) do
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)

    config = %{
      ledger: Keyword.get(opts, :ledger, :memory),
      repo: Keyword.get(opts, :repo),
      adapter: Keyword.get(opts, :adapter, Turnstile.Adapter.Fake)
    }

    [preamble(config, Keyword.get(opts, :async, true)), laws(), transaction(config.ledger)]
  end

  @doc "The head, raising the ledger's error."
  @spec head!(map()) :: non_neg_integer()
  def head!(%{module: module, options: options}) do
    {:ok, head} = module.head(options)
    head
  end

  @doc "Events above a position, raising the ledger's error."
  @spec read!(map(), non_neg_integer(), pos_integer()) :: [FactEvent.t()]
  def read!(%{module: module, options: options}, from, limit) do
    {:ok, events} = module.read(options, from, limit)
    events
  end

  @doc "Append, raising the ledger's error, and answer the stamped events."
  @spec append!(map(), [FactEvent.t()]) :: [FactEvent.t()]
  def append!(%{module: module, options: options}, events) do
    {:ok, stamped} = module.append(options, events)
    stamped
  end

  @doc "An append stamps consecutive positions from the head and moves the head to the last of them."
  @spec law_positions(map(), [FactEvent.t()]) :: true
  def law_positions(context, events) do
    head = head!(context)
    stamped = append!(context, events)
    expected = Enum.to_list((head + 1)..(head + length(events)))

    Enum.map(stamped, & &1.position) == expected and head!(context) == head + length(events)
  end

  @doc "Every appended event reads back as it was appended, with its position stamped."
  @spec law_round_trip(map(), [FactEvent.t()]) :: true
  def law_round_trip(context, events) do
    head = head!(context)
    stamped = append!(context, events)

    read!(context, head, length(events)) == stamped
  end

  @doc false
  @spec __setup__(map(), map()) :: {:ok, keyword()}
  def __setup__(config, tags) do
    if config.repo do
      :ok = Sandbox.setup(config.repo, tags)
    end

    {module, options} = ledger = start_ledger!(config.ledger)
    Mox.stub(Mock, :now, &DateTime.utc_now/0)
    :ok = Turnstile.Test.with_config(adapter: config.adapter, ledger: ledger, clock: Mock)
    {:ok, module: module, options: options, ledger: ledger, repo: config.repo}
  end

  @doc false
  @spec __event__(atom()) :: FactEvent.t()
  def __event__(attribute) do
    %FactEvent{
      kind: :subject_attribute,
      subject_ref: {:user, "11111111-1111-1111-1111-111111111111"},
      object_ref: nil,
      attribute: attribute,
      old: nil,
      new: "cleared",
      position: nil,
      operation_id: "22222222-2222-2222-2222-222222222222",
      at: ~U[2026-09-08 00:00:00.000000Z],
      by: %Turnstile.Subject{id: "11111111-1111-1111-1111-111111111111", kind: :non_person_entity}
    }
  end

  defp preamble(config, async) do
    quote do
      use ExUnit.Case, async: unquote(async)
      use ExUnitProperties

      alias Turnstile.Conformance.Gen
      alias Turnstile.Conformance.LedgerCase

      @ledger_case unquote(Macro.escape(config))

      setup tags do
        unquote(__MODULE__).__setup__(@ledger_case, tags)
      end
    end
  end

  defp laws, do: [empty(), positions(), reads(), round_trip(), options()]

  defp empty do
    quote do
      test "an empty ledger has head 0 and reads nothing", context do
        assert LedgerCase.head!(context) == 0
        assert LedgerCase.read!(context, 0, 10) == []
      end
    end
  end

  defp positions do
    quote do
      property "an append stamps consecutive positions from the head and moves the head", context do
        check all(events <- list_of(Gen.fact_event(), min_length: 1, max_length: 4), max_runs: 25) do
          assert LedgerCase.law_positions(context, events)
        end
      end
    end
  end

  defp reads do
    quote do
      test "a read returns the events above a position, in order, up to the limit", context do
        [first, second, third] = LedgerCase.append!(context, Enum.map([:a, :b, :c], &unquote(__MODULE__).__event__/1))

        assert LedgerCase.read!(context, first.position, 10) == [second, third]
        assert LedgerCase.read!(context, 0, 1) == [first]
        assert LedgerCase.read!(context, third.position, 10) == []
      end
    end
  end

  defp round_trip do
    quote do
      property "an appended event reads back as it was appended", context do
        check all(events <- list_of(Gen.fact_event(), min_length: 1, max_length: 4), max_runs: 25) do
          assert LedgerCase.law_round_trip(context, events)
        end
      end
    end
  end

  defp options do
    quote do
      test "the options schema accepts the case's options and refuses an empty list", context do
        assert {:ok, validated} = NimbleOptions.validate(context.options, context.module.options_schema())
        assert validated[:lock] == "FOR UPDATE"
        assert {:error, %NimbleOptions.ValidationError{}} = NimbleOptions.validate([], context.module.options_schema())
      end
    end
  end

  defp transaction({module, _options}) do
    if Code.ensure_loaded?(module) and function_exported?(module, :transaction, 2), do: transaction_law()
  end

  defp transaction(_ledger), do: nil

  defp transaction_law do
    quote do
      test "transaction answers with the value of its function and keeps what it appended", context do
        head = LedgerCase.head!(context)
        event = unquote(__MODULE__).__event__(:transacted)

        assert {:ok, :done} =
                 context.module.transaction(context.options, fn ->
                   assert [%{position: position}] = LedgerCase.append!(context, [event])
                   assert position == head + 1
                   {:ok, :done}
                 end)

        assert [%{attribute: :transacted}] = LedgerCase.read!(context, head, 10)
      end
    end
  end

  defp start_ledger!(:memory) do
    pid = ExUnit.Callbacks.start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})
    {Memory, agent: pid}
  end

  defp start_ledger!({module, options}) when is_atom(module) and is_list(options), do: {module, options}
end
