defmodule Turnstile.Facts.Record do
  @moduledoc """
  The audit record of one bulk write: which operation on which schema, the
  operation id every event of the write shares, how many rows it touched,
  and the lowest and highest position its events took, both `nil` when it
  wrote no fact. It rides the stop of the write's span, so an application
  that keeps its own audit trail writes one record per bulk write from one
  telemetry handler.
  """

  @enforce_keys [:operation, :schema, :operation_id, :count, :min_position, :max_position, :by, :at]
  defstruct @enforce_keys

  @type operation :: :update | :delete | :insert

  @type t :: %__MODULE__{
          operation: operation(),
          schema: module(),
          operation_id: Turnstile.Id.t(),
          count: non_neg_integer(),
          min_position: pos_integer() | nil,
          max_position: pos_integer() | nil,
          by: Turnstile.subject(),
          at: DateTime.t()
        }
end
