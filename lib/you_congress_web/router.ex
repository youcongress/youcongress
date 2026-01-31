defmodule YouCongressWeb.Router do
  use YouCongressWeb, :router

  import Oban.Web.Router
  import YouCongressWeb.UserAuth

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {YouCongressWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
    plug(:reject_blocked_user)
    plug(:redirect_to_user_registration_if_email_or_phone_unconfirmed)
  end

  pipeline :mcp do
    plug(:accepts, ["json"])
    plug(:fetch_query_params)
    plug(YouCongressWeb.Plugs.MCPSessionPlug)
    plug(YouCongressWeb.Plugs.MCPClusterGuard)
  end

  scope "/" do
    pipe_through(:mcp)

    forward "/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: YouCongressWeb.MCPServer
  end

  scope "/", YouCongressWeb do
    pipe_through(:browser)

    get("/sim", SimController, :index)
    live("/home", StatementLive.Index, :index)
    live("/p/:slug", StatementLive.Show, :show)
    live("/a/:id", AuthorLive.Show, :show)
    live("/x/:twitter_username", AuthorLive.Show, :show)
    live("/halls/:hall", StatementLive.Index, :index)
    live("/c/:id", OpinionLive.Show, :show)
    live("/fact-checker", FactCheckerLive.Index, :index)

    get("/terms", PageController, :terms)
    get("/privacy-policy", PageController, :privacy_policy)

    get("/waiting_list", PageController, :waiting_list)
    get("/about", PageController, :about)
    get("/faq", PageController, :faq)
    get("/email-login-waiting-list", PageController, :email_login_waiting_list)
    get("/email-login-waiting-list/thanks", PageController, :email_login_waiting_list_thanks)
    live("/sign_up", UserRegistrationLive, :new)

    # Legacy redirection from /v/:slug to /p/:slug
    get("/v/:slug", StatementController, :redirect_to_p)
  end

  scope "/", YouCongressWeb do
    pipe_through([:browser, :require_admin_user])

    live("/p/new", StatementLive.Index, :new)
    live("/p/:slug/edit", StatementLive.Show, :edit)
    live("/p/:slug/show/edit", StatementLive.Show, :edit)

    live("/authors", AuthorLive.Index, :index)
    live("/authors/new", AuthorLive.Index, :new)
    live("/authors/:id/edit", AuthorLive.Show, :edit)
    live("/authors/:id/show/edit", AuthorLive.Show, :edit)
  end

  scope "/", YouCongressWeb do
    pipe_through([:browser, :require_admin_or_moderator_user])

    live("/quotes/review", QuoteReviewLive.Index, :index)
  end

  scope "/", YouCongressWeb do
    pipe_through([:browser, :require_authenticated_user])

    live("/welcome", WelcomeLive.Index, :index)
    live("/p/:slug/add-quote", StatementLive.AddQuote, :add_quote)

    live("/settings", SettingsLive, :settings)
    live("/landing", HomeLive.Index, :index)
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
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: YouCongressWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  ## Authentication routes

  # OAuth routes
  scope "/auth", YouCongressWeb do
    pipe_through([:browser])

    get("/x", XAuthController, :request)
    get("/x/callback", XAuthController, :callback)
    get("/google", GoogleAuthController, :request)
    get("/google/callback", GoogleAuthController, :callback)
  end

  scope "/", YouCongressWeb do
    pipe_through([:browser, :redirect_home_if_user_is_authenticated])

    live("/", HomeLive.Index, :index)
  end

  scope "/", YouCongressWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{YouCongressWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live("/log_in", UserLoginLive, :new)
    end

    post("/log_in", UserSessionController, :create)
  end

  scope "/", YouCongressWeb do
    pipe_through([:browser, :fetch_current_user, :redirect_if_user_is_authenticated])

    live("/reset_password", ResetPasswordLive, :new)
    live("/reset_password/:token", ResetPasswordTokenLive, :edit)
  end

  scope "/", YouCongressWeb do
    pipe_through([:browser])

    get("/log_out", UserSessionController, :delete)
    delete("/log_out", UserSessionController, :delete)
    get("/users/confirm/:token", UserConfirmationController, :confirm)

    live_session :current_user,
      on_mount: [{YouCongressWeb.UserAuth, :mount_current_user}] do
    end
  end
end
