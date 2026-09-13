defmodule Example.Router do
  @moduledoc "The web layer: JSON routes behind the identity plug; every route's authorization is the context's."

  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
    plug Example.Plug.Identity
  end

  scope "/", Example do
    pipe_through :api

    get "/documents", DocumentController, :index
    get "/documents/:id", DocumentController, :show
    get "/documents/:id/redacted", DocumentController, :redacted
    put "/documents/:id/marking", DocumentController, :marking
    post "/documents/:id/override", DocumentController, :override
    post "/documents/:id/proposals", ProposalController, :create
    post "/proposals/:id/approve", ProposalController, :approve
  end
end
