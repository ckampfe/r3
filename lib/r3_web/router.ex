defmodule R3Web.Router do
  use R3Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {R3Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", R3Web do
    pipe_through :browser

    get "/", ReaderController, :index
    post "/feeds", ReaderController, :feed_create
    get "/feeds/:feed_id", ReaderController, :feed_show
    put "/feeds/:feed_id/refresh", ReaderController, :feed_refresh
    get "/entries/:entry_id", ReaderController, :entry_show
    put "/entries/:entry_id/toggle_read_at", ReaderController, :entry_toggle_read_at
    delete "/empty", ReaderController, :empty
  end

  # Other scopes may use custom stacks.
  # scope "/api", R3Web do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:r3, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: R3Web.Telemetry
    end
  end
end
