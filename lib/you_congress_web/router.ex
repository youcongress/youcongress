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
    plug :redirect_to_user_registration_if_email_or_phone_unconfirmed
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", YouCongressWeb do
    pipe_through :browser

    live "/activity", HomeLive.Index, :index
    live "/p/:slug", VotingLive.Show, :show
    live "/a/:id", AuthorLive.Show, :show
    live "/x/:twitter_username", AuthorLive.Show, :show
    live "/", VotingLive.Index, :index
    live "/halls/:hall", VotingLive.Index, :index
    live "/comments/:id", OpinionLive.Show, :show

    get "/terms", PageController, :terms
    get "/privacy-policy", PageController, :privacy_policy

    get "/waiting_list", PageController, :waiting_list
    get "/about", PageController, :about
    post "/x_log_in", TwitterLogInController, :log_in
    get "/twitter-callback", TwitterLogInController, :callback
    get "/faq", PageController, :faq
    get "/email-login-waiting-list", PageController, :email_login_waiting_list
    get "/email-login-waiting-list/thanks", PageController, :email_login_waiting_list_thanks
    get "/members", PageController, :members
    get "/members/thanks", PageController, :members_thanks
    live "/sign_up", UserRegistrationLive, :new

    # Legacy redirection from /v/:slug to /p/:slug
    get "/v/:slug", VotingController, :redirect_to_p
  end

  scope "/", YouCongressWeb do
    pipe_through [:browser, :require_admin_user]

    live "/p/new", VotingLive.Index, :new
    live "/p/:slug/edit", VotingLive.Show, :edit
    live "/p/:slug/show/edit", VotingLive.Show, :edit

    live "/authors", AuthorLive.Index, :index
    live "/authors/new", AuthorLive.Index, :new
    live "/authors/:id/edit", AuthorLive.Show, :edit
    live "/authors/:id/show/edit", AuthorLive.Show, :edit
  end

  scope "/", YouCongressWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/welcome", WelcomeLive.Index, :index
    live "/p/:slug/add-quote", VotingLive.AddQuote, :add_quote

    live "/settings", SettingsLive, :settings
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
      live "/log_in", UserLoginLive, :new
    end

    post "/log_in", UserSessionController, :create
  end

  scope "/", YouCongressWeb do
    pipe_through [:browser, :fetch_current_user, :redirect_if_user_is_authenticated]

    live "/reset_password", ResetPasswordLive, :new
    live "/reset_password/:token", ResetPasswordTokenLive, :edit
  end

  scope "/", YouCongressWeb do
    pipe_through [:browser]

    get "/log_out", UserSessionController, :delete
    delete "/log_out", UserSessionController, :delete
    get "/users/confirm/:token", UserConfirmationController, :confirm

    live_session :current_user,
      on_mount: [{YouCongressWeb.UserAuth, :mount_current_user}] do
    end
  end
end
