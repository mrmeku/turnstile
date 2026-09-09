defmodule Example.DocumentController do
  @moduledoc "Documents over JSON. The subject and the facts come from the identity plug; the verdict from the context."

  use Phoenix.Controller, formats: [:json]

  alias Example.Controls
  alias Example.Document
  alias Example.Documents
  alias Example.Portion

  @doc "The documents the subject may read."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    documents = Documents.list(subject(conn), options(conn))
    json(conn, %{documents: Enum.map(documents, &document/1)})
  end

  @doc "One document with its banner."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    respond(conn, Documents.read(subject(conn), parse(id), options(conn)))
  end

  @doc "One document with the portions the subject may read."
  @spec redacted(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def redacted(conn, %{"id" => id}) do
    respond(conn, Documents.read_redacted(subject(conn), parse(id), options(conn)))
  end

  @doc "Change the banner."
  @spec marking(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def marking(conn, %{"id" => id} = params) do
    respond(conn, Documents.change_marking(subject(conn), parse(id), Map.delete(params, "id"), options(conn)))
  end

  @doc "The audited override."
  @spec override(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def override(conn, %{"id" => id} = params) do
    justification = Map.get(params, "justification", "")
    respond(conn, Documents.override_read(subject(conn), parse(id), justification, options(conn)))
  end

  defp respond(conn, {:ok, %Document{} = document}), do: json(conn, document(document))
  defp respond(conn, {:ok, %Example.Marking{} = marking}), do: json(conn, Controls.marking(marking))
  defp respond(conn, {:error, :not_found}), do: error(conn, 404, "not found")
  defp respond(conn, {:error, %Documents.BannerViolation{}}), do: error(conn, 422, "banner")
  defp respond(conn, {:error, _refusal}), do: error(conn, 403, "forbidden")

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end

  defp document(%Document{} = document) do
    %{
      id: document.id,
      title: document.title,
      decontrol: document.decontrol,
      marking: marking(document.marking),
      portions: portions(document.portions)
    }
  end

  defp marking(%Example.Marking{} = marking), do: Map.put(Controls.marking(marking), :list, marking.list)
  defp marking(_unloaded), do: nil

  defp portions(portions) when is_list(portions) do
    Enum.map(portions, fn %Portion{} = portion -> Map.put(Controls.marking(portion), :body, portion.body) end)
  end

  defp portions(_unloaded), do: []

  defp subject(conn), do: conn.assigns.subject
  defp options(conn), do: [facts: conn.assigns.facts]
  defp parse(id) when is_binary(id), do: String.to_integer(id)
end
