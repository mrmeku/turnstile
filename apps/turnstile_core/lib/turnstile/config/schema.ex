defmodule Turnstile.Config.Schema do
  @moduledoc false
  # The NimbleOptions schema behind `Turnstile.Config`, in its own module so
  # the config's moduledoc can render it.

  @schema NimbleOptions.new!(
            adapter: [
              type: {:or, [:atom, {:tuple, [:atom, :keyword_list]}]},
              required: true,
              doc: "The module implementing `Turnstile.Adapter`, bare or with its options."
            ],
            ledger: [
              type: {:or, [{:in, [:none]}, {:tuple, [:atom, :keyword_list]}]},
              required: true,
              doc: "`{module, options}` for a module implementing `Turnstile.Ledger`, or `:none`."
            ],
            ledger_counter: [
              type: :string,
              default: "default",
              doc: "The counter row's name; a test override, left at the default by applications."
            ],
            clock: [type: :atom, doc: "The module implementing `Turnstile.Clock`; `Turnstile.Clock.System` when absent."],
            caps: [
              type: :keyword_list,
              default: [batch_ids: 1_000, rule_bytes: 4_096, policy_content_bytes: 65_536],
              keys: [
                batch_ids: [type: :pos_integer, default: 1_000, doc: "Ids listed in a record."],
                rule_bytes: [type: :pos_integer, default: 4_096, doc: "Rule text kept in a record."],
                policy_content_bytes: [type: :pos_integer, default: 65_536, doc: "Policy text kept by value."]
              ],
              doc: "The caps on what a record carries by value."
            ]
          )

  @doc false
  @spec schema() :: NimbleOptions.t()
  def schema, do: @schema
end
