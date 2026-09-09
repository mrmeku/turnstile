defmodule Example.Plug.Identity do
  @moduledoc """
  The identity-only plug. It reads the caller's account id, session id, and
  re-authentication time from headers an authenticating proxy sets, builds
  the subject from the account's row, and assigns the subject and the facts
  the port receives. It authorizes nothing: every rule is asked at the port
  by the contexts.
  """

  @behaviour Plug

  import Plug.Conn

  alias Example.Accounts

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{} = conn, _opts) do
    with [user_id] <- get_req_header(conn, "x-user-id"),
         %Turnstile.Subject{} = subject <- Accounts.subject(user_id, session_id(conn)) do
      conn
      |> assign(:subject, subject)
      |> assign(:facts, facts(conn))
    else
      _absent ->
        conn
        |> send_resp(401, "unidentified")
        |> halt()
    end
  end

  defp session_id(conn) do
    case get_req_header(conn, "x-session-id") do
      [id] -> id
      _absent -> nil
    end
  end

  defp facts(conn) do
    with [at] <- get_req_header(conn, "x-reauthenticated-at"),
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      %{reauthenticated_at: at}
    else
      _absent -> %{}
    end
  end
end
