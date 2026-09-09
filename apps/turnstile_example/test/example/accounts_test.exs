defmodule Example.AccountsTest do
  use Example.FakeCase, async: true

  alias Example.Accounts
  alias Example.Assignment
  alias Example.OfficeRole
  alias Example.User
  alias Turnstile.Subject

  test "the subject of an account carries the account's kind and the session", %{} do
    assert %Subject{id: "gil", kind: :privileged, session_id: "s1"} = Accounts.subject("gil", "s1")
    assert %Subject{id: "ann", kind: :user, session_id: nil} = Accounts.subject("ann")
    assert Accounts.subject("nobody") == nil
  end

  test "assignments and office roles are granted and revoked as rows", %{world: world} do
    assert %Assignment{role: :lead} = Accounts.assign("frank", world.program.id, :lead)
    assert Accounts.unassign("frank", world.program.id) == 1
    assert Accounts.unassign("frank", world.program.id) == 0
    assert %OfficeRole{role: :approver} = Accounts.office_role("frank", world.office.id, :approver)
  end

  test "the override permission is a row, and privileged accounts are listed with their roles", %{} do
    refute Accounts.override_permitted?("frank")
    assert Accounts.override_permitted?("gil")
    assert [{%User{id: "gil", person_id: "gil"}, [:override]}] = Accounts.privileged()
  end

  test "employment and nationality are corrected in place", %{} do
    assert %User{employment: :contractor} = Accounts.set_employment("ann", :contractor)
    assert %User{nationality: "FR"} = Accounts.set_nationality("ann", "FR")
    assert %User{employment: :contractor, nationality: "FR"} = Example.Repo.get(User, "ann")
  end
end
