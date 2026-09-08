defmodule Turnstile.Subject do
  @moduledoc """
  Who is asking. A person, software acting alone, or a person who can change
  the system; the kind travels with every decision record.
  """

  @enforce_keys [:id, :kind]
  defstruct [:id, :kind, session_id: nil]

  @typedoc "A person, a non-person entity, or a privileged person."
  @type kind :: :user | :non_person_entity | :privileged

  @type t :: %__MODULE__{
          id: Turnstile.Id.t(),
          kind: kind(),
          session_id: Turnstile.Id.t() | nil
        }

  @doc "The three kinds, in the order the reference lists them."
  @spec kinds() :: [kind()]
  def kinds, do: [:user, :non_person_entity, :privileged]

  @doc "The subject's reference as facts name it: `{:user, id}` for every kind."
  @spec ref(t()) :: {:user, Turnstile.Id.t()}
  def ref(%__MODULE__{id: id}), do: {:user, id}
end
