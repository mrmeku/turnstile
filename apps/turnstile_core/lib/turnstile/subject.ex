defmodule Turnstile.Subject do
  @moduledoc """
  Who is asking. A person, software acting alone, or a person who can change
  the system; the kind travels with every decision record.
  """

  alias Turnstile.Edge
  alias Turnstile.Error

  @library_id "00000000-0000-0000-0000-000000000000"

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

  @doc """
  The subject of a write made under an exemption, where no decision names
  one: the library itself, a non-person entity with the nil identifier.
  """
  @spec library() :: t()
  def library, do: %__MODULE__{id: @library_id, kind: :non_person_entity}

  @doc "The subject's reference as facts name it: `{:user, id}` for every kind."
  @spec ref(t()) :: {:user, Turnstile.Id.t()}
  def ref(%__MODULE__{id: id}), do: {:user, id}

  @doc "The subject as a map of plain values."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{id: id, kind: kind, session_id: session_id}) do
    %{id: id, kind: Atom.to_string(kind), session_id: session_id}
  end

  @doc "A map back to the subject."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def from_map(map) when is_map(map) do
    with {:ok, [id, kind]} <- Edge.fetch_all(map, [:id, :kind], :subject),
         {:ok, id} <- Edge.string_in(id, :subject, false),
         {:ok, kind} <- Edge.atom_in(kind, :subject),
         {:ok, session_id} <- Edge.string_in(session_of(map), :subject, true) do
      {:ok, %__MODULE__{id: id, kind: kind, session_id: session_id}}
    end
  end

  defp session_of(map) do
    case Edge.fetch(map, :session_id) do
      {:ok, session_id} -> session_id
      :error -> nil
    end
  end
end
