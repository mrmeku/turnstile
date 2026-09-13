defmodule Turnstile.Facts.Context do
  @moduledoc false
  # What every bulk write needs: where it writes, what it writes to, the
  # ledger it appends to, and the stamp its events carry.

  @enforce_keys [:repo, :schema, :ledger, :options, :stamp, :opts]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          repo: module(),
          schema: module(),
          ledger: module() | :none,
          options: keyword(),
          stamp: %{by: Turnstile.Subject.t(), operation_id: Turnstile.Id.t(), at: DateTime.t()},
          opts: keyword()
        }
end
