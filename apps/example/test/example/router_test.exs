defmodule Example.RouterTest do
  use Example.FakeCase, async: true

  import Plug.Conn
  import Plug.Test

  alias Example.Fixture
  alias Example.Router

  setup %{world: world} do
    {:ok, document: Fixture.document!(world, portions: [%{body: "open"}])}
  end

  defp request(method, path, user, params \\ nil) do
    method
    |> conn(path, params)
    |> put_req_header("x-user-id", user)
    |> put_req_header("accept", "application/json")
    |> Router.call(Router.init([]))
  end

  defp body(conn), do: JSON.decode!(conn.resp_body)

  test "index and show return what the contexts allow", ctx do
    id = ctx.document.id
    assert %{"documents" => []} = body(request(:get, "/documents", "ann"))
    assert request(:get, "/documents/#{id}", "ann").status == 403
    allow(ctx.rules, "ann", :read, {:document, id})
    assert %{"documents" => [%{"id" => ^id, "marking" => %{"controls" => []}}]} = body(request(:get, "/documents", "ann"))
    assert %{"id" => ^id, "title" => "document", "portions" => []} = body(request(:get, "/documents/#{id}", "ann"))
    allow(ctx.rules, "ann", :read, {:document, :any})
    assert request(:get, "/documents/#{id + 1000}", "ann").status == 404
  end

  test "redacted returns the readable portions", ctx do
    id = ctx.document.id
    [portion] = ctx.document.portions
    allow(ctx.rules, "carl", :read_redacted, {:document, id})
    assert %{"portions" => []} = body(request(:get, "/documents/#{id}/redacted", "carl"))
    allow(ctx.rules, "carl", :read, {:portion, portion.id})
    assert %{"portions" => [%{"body" => "open"}]} = body(request(:get, "/documents/#{id}/redacted", "carl"))
  end

  test "marking changes answer 200, 403, and 422", ctx do
    id = ctx.document.id
    assert request(:put, "/documents/#{id}/marking", "dana", %{"controls" => ["no_foreign"]}).status == 403
    allow(ctx.rules, "dana", :change_marking, {:document, id})
    conn = request(:put, "/documents/#{id}/marking", "dana", %{"controls" => ["no_foreign"]})
    assert conn.status == 200 and body(conn) == %{"categories" => [], "controls" => ["no_foreign"], "releasable_to" => []}
    document = Fixture.document!(ctx.world, portions: [%{body: "x", controls: [:federal_only]}])
    allow(ctx.rules, "dana", :change_marking, {:document, document.id})
    assert request(:put, "/documents/#{document.id}/marking", "dana", %{"controls" => []}).status == 422
  end

  test "the override answers 200 with the document and 403 without a justification", ctx do
    id = ctx.document.id
    assert request(:post, "/documents/#{id}/override", "gil", %{}).status == 403
    assert %{"id" => ^id} = body(request(:post, "/documents/#{id}/override", "gil", %{"justification" => "why"}))
    assert request(:post, "/documents/#{id}/override", "ann", %{"justification" => "why"}).status == 403
  end

  test "proposals are created and approved", ctx do
    id = ctx.document.id
    assert request(:post, "/documents/#{id}/proposals", "dana", %{"controls" => ["no_foreign"]}).status == 403
    allow(ctx.rules, "dana", :propose_marking, {:document, id})
    conn = request(:post, "/documents/#{id}/proposals", "dana", %{"controls" => ["no_foreign"]})
    assert conn.status == 201
    assert %{"id" => proposal_id, "status" => "pending"} = body(conn)
    assert request(:post, "/proposals/#{proposal_id}/approve", "eve").status == 403
    allow(ctx.rules, "eve", :approve_marking, {:proposal, proposal_id})
    assert %{"controls" => ["no_foreign"]} = body(request(:post, "/proposals/#{proposal_id}/approve", "eve"))
  end

  test "an unidentified caller is refused before any route", %{} do
    conn = Router.call(conn(:get, "/documents"), Router.init([]))
    assert conn.status == 401
  end
end
