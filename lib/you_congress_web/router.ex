defmodule YouCongressWeb.Router do
  use YouCongressWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YouCongressWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", YouCongressWeb do
    pipe_through :browser

    live "/authors", AuthorLive.Index, :index
    live "/authors/new", AuthorLive.Index, :new
    live "/authors/:id/edit", AuthorLive.Index, :edit
    live "/authors/:id", AuthorLive.Show, :show
    live "/authors/:id/show/edit", AuthorLive.Show, :edit

    live "/", VotingLive.Index, :index
    live "/votings/new", VotingLive.Index, :new
    live "/votings/:id/edit", VotingLive.Index, :edit
    live "/votings/:id", VotingLive.Show, :show
    live "/votings/:id/show/edit", VotingLive.Show, :edit

    live "/opinions", OpinionLive.Index, :index
    live "/opinions/new", OpinionLive.Index, :new
    live "/opinions/:id/edit", OpinionLive.Index, :edit
    live "/opinions/:id", OpinionLive.Show, :show
    live "/opinions/:id/show/edit", OpinionLive.Show, :edit
  end

  # Other scopes may use custom stacks.
  # scope "/api", YouCongressWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:you_congress, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: YouCongressWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
