defmodule Turnstile.Domain.ConfigSchema do
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
