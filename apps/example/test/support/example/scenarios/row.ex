defmodule Example.Scenarios.Row do
  @moduledoc "One row of the scenario table in `docs/example.md` §4: the id, the sentence, the group, the controls cited, and what it tests."

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
