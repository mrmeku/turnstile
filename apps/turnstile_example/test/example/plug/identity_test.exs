defmodule Example.Plug.IdentityTest do
  use Example.FakeCase, async: true

  import Plug.Conn
  import Plug.Test

  alias Example.Plug.Identity

  test "the subject and the facts come from the headers", %{} do
    conn =
      :get
      |> conn("/")
      |> put_req_header("x-user-id", "gil")
      |> put_req_header("x-session-id", "s1")
      |> put_req_header("x-reauthenticated-at", "2026-09-08T12:00:00Z")
      |> Identity.call(Identity.init([]))

    refute conn.halted
    assert conn.assigns.subject == %Turnstile.Subject{id: "gil", kind: :privileged, session_id: "s1"}
    assert conn.assigns.facts == %{reauthenticated_at: ~U[2026-09-08 12:00:00Z]}
  end

  test "no session and no re-authentication header give a bare subject and no facts", %{} do
    conn = identified("ann")
    assert conn.assigns.subject == %Turnstile.Subject{id: "ann", kind: :user, session_id: nil}
    assert conn.assigns.facts == %{}

    conn =
      :get
      |> conn("/")
      |> put_req_header("x-user-id", "ann")
      |> put_req_header("x-reauthenticated-at", "soon")
      |> Identity.call([])

    assert conn.assigns.facts == %{}
  end

  test "a missing or unknown account is refused with 401", %{} do
    conn = Identity.call(conn(:get, "/"), [])
    assert conn.halted and conn.status == 401
    conn = identified("nobody")
    assert conn.halted and conn.status == 401
  end

  defp identified(user_id) do
    :get
    |> conn("/")
    |> put_req_header("x-user-id", user_id)
    |> Identity.call([])
  end
end
