defmodule Turnstile.Conformance.Scenario do
  @moduledoc "One row of the Tier 2 scenario table: the id, the sentence, the group, the controls cited, and what it tests."

  @enforce_keys [:id, :sentence, :group, :controls, :tests]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          sentence: String.t(),
          group: atom(),
          controls: [String.t()],
          tests: [atom()]
        }
end
