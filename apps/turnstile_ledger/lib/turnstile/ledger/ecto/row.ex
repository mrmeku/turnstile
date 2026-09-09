defmodule Turnstile.Ledger.Ecto.Row do
  @moduledoc """
  One row of `turnstile_ledger_events`, and the two conversions between a
  row and a `Turnstile.FactEvent`. The event's refs and values are tagged by
  `Turnstile.Ledger.Ecto.Value`; a policy version goes in as its own map,
  which is what `Turnstile.FactEvent.from_map/1` reads it back from.

  The row carries a serial id beside the position, because genesis writes
  every current fact at position zero: the position orders what the ledger
  hands a reader, and the id orders what shares a position.
  """

  use Ecto.Schema

  alias Turnstile.Edge
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Ecto.Value
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject

  @type t :: %__MODULE__{}

  schema "turnstile_ledger_events" do
    field :position, :integer
    field :kind, :string
    field :subject_ref, :map
    field :object_ref, :map
    field :attribute, :string
    field :old, :map
    field :new, :map
    field :operation_id, :string
    field :at, :utc_datetime_usec
    field :by, :map
  end

  @doc "The event as the columns hold it, for one insert of many rows."
  @spec dump(FactEvent.t()) :: map()
  def dump(%FactEvent{} = event) do
    %{
      position: event.position,
      kind: Atom.to_string(event.kind),
      subject_ref: Value.ref_dump(event.subject_ref),
      object_ref: Value.ref_dump(event.object_ref),
      attribute: Edge.atom_out(event.attribute),
      old: value_dump(event.old),
      new: value_dump(event.new),
      operation_id: event.operation_id,
      at: event.at,
      by: Subject.to_map(event.by)
    }
  end

  @doc "A row back to the event that was appended."
  @spec load(t()) :: {:ok, FactEvent.t()} | {:error, Error.Invalid.t()}
  def load(%__MODULE__{} = row) do
    with {:ok, subject_ref} <- Value.ref_load(row.subject_ref),
         {:ok, object_ref} <- Value.ref_load(row.object_ref),
         {:ok, old} <- value_load(row.old),
         {:ok, new} <- value_load(row.new) do
      FactEvent.from_map(%{
        kind: row.kind,
        subject_ref: subject_ref,
        object_ref: object_ref,
        attribute: row.attribute,
        old: old,
        new: new,
        position: row.position,
        operation_id: row.operation_id,
        at: row.at,
        by: row.by
      })
    end
  end

  defp value_dump(%PolicyVersion{} = version), do: %{"v" => PolicyVersion.to_map(version)}
  defp value_dump(value), do: Value.dump(value)

  # A policy version is a map of plain values in the column and a struct
  # again in the event, which `FactEvent.from_map/1` does by kind.
  defp value_load(%{"v" => %{"adapter" => _adapter} = version}), do: {:ok, version}
  defp value_load(stored), do: Value.load(stored)
end
