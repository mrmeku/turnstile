defmodule Turnstile.Ledger.FoldTest do
  use ExUnit.Case, async: true

  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Fold
  alias Turnstile.Subject

  @user {:user, "acct-a"}
  @folder {:folder, 1}

  defp event(position, fields) do
    struct!(
      %FactEvent{
        kind: :relationship,
        subject_ref: @user,
        object_ref: @folder,
        attribute: nil,
        old: nil,
        new: :reader,
        position: position,
        operation_id: "op-#{position}",
        at: DateTime.shift(~U[2026-01-01 00:00:00Z], second: position),
        by: Subject.library()
      },
      fields
    )
  end

  test "an empty fold has no facts, position 0, and no time" do
    assert %Fold{facts: %{}, position: 0, at: nil} = Fold.empty()
    assert Fold.fold([]) == Fold.empty()
  end

  test "a relationship is a fact keyed on subject and object; its deletion removes the fact" do
    inserted = event(1, [])
    deleted = event(2, old: :reader, new: nil)
    assert %Fold{facts: %{{@user, @folder, nil} => :reader}, position: 1} = Fold.fold([inserted])
    assert %Fold{facts: %{}, position: 2, at: at} = Fold.fold([inserted, deleted])
    assert at == deleted.at
  end

  test "a relationship attribute change replaces a single value or updates a map of values" do
    inserted = event(1, [])
    changed = event(2, attribute: :role, old: :reader, new: :editor)
    assert %Fold{facts: %{{@user, @folder, nil} => :editor}} = Fold.fold([inserted, changed])

    with_map = event(1, new: %{role: :reader, since: 2026})
    assert %Fold{facts: %{{@user, @folder, nil} => %{role: :editor, since: 2026}}} = Fold.fold([with_map, changed])
    assert %Fold{facts: %{{@user, @folder, nil} => :editor}} = Fold.fold([changed])
  end

  test "subject and object attributes are keyed on their attribute name" do
    cleared = event(1, kind: :subject_attribute, object_ref: nil, attribute: :clearance, new: "cleared")
    marked = event(2, kind: :object_attribute, subject_ref: nil, attribute: :marking, new: "secret")
    removed = event(3, kind: :subject_attribute, object_ref: nil, attribute: :clearance, old: "cleared", new: nil)

    assert %Fold{facts: facts} = Fold.fold([cleared, marked, removed])
    assert facts == %{{nil, @folder, :marking} => "secret"}
  end

  test "fold_into continues from a fold; at and to stop at a time or a position" do
    events = [event(1, []), event(2, attribute: :role, old: :reader, new: :editor), event(3, old: :editor, new: nil)]
    first = Fold.fold(Enum.take(events, 1))
    assert Fold.fold_into(first, Enum.drop(events, 1)) == Fold.fold(events)

    assert %Fold{position: 2, facts: %{{@user, @folder, nil} => :editor}} = Fold.to(events, 2)
    assert %Fold{position: 0, facts: %{}} = Fold.to(events, 0)
    assert %Fold{position: 1} = Fold.at(events, ~U[2026-01-01 00:00:01.5Z])
    assert %Fold{position: 3, facts: %{}} = Fold.at(events, ~U[2026-01-01 00:01:00Z])
    assert %Fold{position: 0} = Fold.at(events, ~U[2025-12-31 00:00:00Z])
  end
end
