defmodule Turnstile.Core.ConfigSchema do
  @moduledoc false
  # The NimbleOptions schema behind `Turnstile.Config`, in its own module so
  # the config's moduledoc can render it. What the fields mean is written
  # here, and the struct is built from what this validates.

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
            clock: [
              type: {:fun, 0},
              doc: "A zero-arity function answering the current time in UTC; `&DateTime.utc_now/0` when absent."
            ],
            caps: [
              type: :keyword_list,
              default: [policy_content_bytes: 65_536],
              keys: [
                policy_content_bytes: [type: :pos_integer, default: 65_536, doc: "Policy text kept by value."]
              ],
              doc: "The caps on what a record carries by value."
            ]
          )

  @doc false
  @spec schema() :: NimbleOptions.t()
  def schema, do: @schema
end
