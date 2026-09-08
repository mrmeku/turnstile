defmodule Turnstile.Adapter.Fake do
  @moduledoc """
  The adapter Tier 1 runs first and the seam's tests bind. It answers every
  question with the configured verdict and returns a value of the real type
  everywhere the real adapters do: `scope` returns a real `dynamic`, `explain`
  returns `Turnstile.Error.Unsupported`.
  """

  @behaviour Turnstile.Adapter

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Scope
  alias Turnstile.Subject

  @version "fake"

  @schema NimbleOptions.new!(verdict: [type: {:in, [:allow, :deny]}, default: :deny, doc: "The answer to everything."])

  @impl Turnstile.Adapter
  def options_schema, do: @schema

  @impl Turnstile.Adapter
  def requires_ledger, do: false

  @impl Turnstile.Adapter
  def scope_cap, do: :none

  @impl Turnstile.Adapter
  def authorize(%Subject{}, operation, %Object{}, %Environment{}, options) when is_atom(operation) do
    {:ok, answer(options)}
  end

  @impl Turnstile.Adapter
  def check(%Subject{}, operation, %Object{}, %Environment{}, options) when is_atom(operation) do
    {:ok, answer(options)}
  end

  @impl Turnstile.Adapter
  def batch(%Subject{}, operation, objects, %Environment{}, options) when is_atom(operation) and is_list(objects) do
    answer = answer(options)
    {:ok, Map.new(objects, fn %Object{} = object -> {Object.ref(object), answer} end)}
  end

  @impl Turnstile.Adapter
  def scope(%Subject{}, operation, object_type, %Environment{}, options)
      when is_atom(operation) and is_atom(object_type) do
    answer = answer(options)

    rule =
      case answer.verdict do
        :allow -> dynamic([_row], true)
        :deny -> dynamic([_row], false)
      end

    {:ok, %Scope{rule: rule, answer: answer}}
  end

  @impl Turnstile.Adapter
  def explain(%Subject{}, operation, %Object{}, %Environment{}, _options) when is_atom(operation) do
    {:error, %Error.Unsupported{adapter: __MODULE__, feature: :explain, note: "the fake names no rule"}}
  end

  @doc "The answer the fake gives under these options; `Turnstile.Explanation` is never built from it."
  @spec answer(keyword()) :: Answer.t()
  def answer(options) when is_list(options) do
    case Keyword.get(options, :verdict, :deny) do
      :allow ->
        %Answer{verdict: :allow, reason: Reason.allowed("fake"), policy_version: @version, applied_position: nil}

      :deny ->
        %Answer{verdict: :deny, reason: Reason.deny_by_default(), policy_version: @version, applied_position: nil}
    end
  end
end
