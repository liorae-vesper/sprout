defmodule SproutWeb.Router do
  use SproutWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SproutWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :developer_portal do
    plug SproutWeb.DeveloperPortalAccess
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SproutWeb do
    pipe_through :browser

    live "/", DashboardLive
  end

  scope "/", SproutWeb do
    pipe_through [:browser, :developer_portal]
    live "/developers", DeveloperPortalLive
  end

  scope "/api", SproutWeb do
    pipe_through :api
    get "/openapi.json", APIContractController, :show
  end

  scope "/api/v1", SproutWeb do
    pipe_through [:api, SproutWeb.IntegrationAuth]
    get "/fields", IntegrationAPIController, :fields
    get "/fields/:field_id/readings", IntegrationAPIController, :readings
    post "/fields/:field_id/readings", IntegrationAPIController, :create_reading
  end
end
