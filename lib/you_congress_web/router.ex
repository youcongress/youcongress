defmodule YouCongressWeb.Router do
  use YouCongressWeb, :router

  import YouCongressWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YouCongressWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
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

    live "/votes", VoteLive.Index, :index
    live "/votes/new", VoteLive.Index, :new
    live "/votes/:id/edit", VoteLive.Index, :edit
    live "/votes/:id", VoteLive.Show, :show
    live "/votes/:id/show/edit", VoteLive.Show, :edit
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

  ## Authentication routes

  scope "/", YouCongressWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{YouCongressWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/sign_up", UserRegistrationLive, :new
      live "/log_in", UserLoginLive, :new
      live "/reset_password", UserForgotPasswordLive, :new
      live "/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/log_in", UserSessionController, :create
  end

  scope "/", YouCongressWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{YouCongressWeb.UserAuth, :ensure_authenticated}] do
      live "/settings", UserSettingsLive, :edit
      live "/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", YouCongressWeb do
    pipe_through [:browser]

    delete "/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{YouCongressWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
