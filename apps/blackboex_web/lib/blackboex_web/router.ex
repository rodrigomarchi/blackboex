defmodule BlackboexWeb.Router do
  use BlackboexWeb, :router

  import BlackboexWeb.UserAuth
  import Backpex.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BlackboexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :audit_context do
    plug BlackboexWeb.Plugs.AuditContext
  end

  pipeline :require_platform_admin do
    plug BlackboexWeb.Plugs.RequirePlatformAdmin
  end

  pipeline :set_organization do
    plug BlackboexWeb.Plugs.SetOrganization
  end

  pipeline :admin_layout do
    plug :put_root_layout, html: {BlackboexWeb.Layouts, :admin_root}
  end

  scope "/", BlackboexWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Public API landing pages — no auth required
  scope "/p", BlackboexWeb do
    pipe_through :browser
    get "/:org_slug/:api_slug", PublicApiController, :show
  end

  # Flow webhook — public, no auth, no CSRF
  scope "/webhook", BlackboexWeb do
    pipe_through :api
    post "/:token", FlowWebhookController, :execute
  end

  # Flow execution API — authenticated via session + org scope
  scope "/api/v1", BlackboexWeb do
    pipe_through [:browser, :require_authenticated_user, :set_organization]
    get "/flows/:slug/executions", FlowExecutionController, :index
    get "/executions/:id", FlowExecutionController, :show
  end

  # Dynamic API routing — forwards all /api/* requests to the DynamicApiRouter
  scope "/api" do
    pipe_through :api
    forward "/", BlackboexWeb.Plugs.DynamicApiRouter
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:blackboex_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BlackboexWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Stripe webhooks — no auth, no CSRF, signature verified in controller
  scope "/webhooks", BlackboexWeb do
    pipe_through :api
    post "/stripe", WebhookController, :handle
  end

  # Backpex cookie route
  scope "/" do
    pipe_through :browser
    backpex_routes()
  end

  # Admin panel — platform admins only
  scope "/admin", BlackboexWeb.Admin do
    pipe_through [
      :browser,
      :admin_layout,
      :require_authenticated_user,
      :require_platform_admin,
      :audit_context
    ]

    live_session :admin,
      layout: false,
      on_mount: [
        {BlackboexWeb.UserAuth, :require_authenticated},
        {BlackboexWeb.Hooks.SetOrganization, :default},
        Backpex.InitAssigns
      ] do
      live "/", DashboardLive, :index

      # Core
      live_resources "/users", UserLive
      live_resources "/user-tokens", UserTokenLive
      live_resources "/organizations", OrganizationLive
      live_resources "/memberships", MembershipLive
      live_resources "/apis", ApiLive
      live_resources "/subscriptions", SubscriptionLive

      # API data
      live_resources "/api-keys", ApiKeyLive
      live_resources "/api-versions", ApiVersionLive
      live_resources "/agent-conversations", AgentConversationLive
      live_resources "/agent-runs", AgentRunLive
      live_resources "/agent-events", AgentEventLive
      live_resources "/data-store-entries", DataStoreEntryLive
      live_resources "/invocation-logs", InvocationLogLive
      live_resources "/metric-rollups", MetricRollupLive

      # Billing
      live_resources "/daily-usage", DailyUsageLive
      live_resources "/usage-events", UsageEventLive
      live_resources "/processed-events", ProcessedEventLive

      # Testing
      live_resources "/test-requests", TestRequestLive
      live_resources "/test-suites", TestSuiteLive

      # LLM
      live_resources "/llm-usage", LlmUsageLive

      # Audit
      live_resources "/audit-logs", AuditLogLive
      live_resources "/versions", VersionLive
    end
  end

  ## Authentication routes

  scope "/", BlackboexWeb do
    pipe_through [:browser, :require_authenticated_user, :audit_context]

    live_session :require_authenticated_user,
      layout: {BlackboexWeb.Layouts, :app},
      on_mount: [
        {BlackboexWeb.UserAuth, :require_authenticated},
        {BlackboexWeb.Hooks.SetOrganization, :default}
      ] do
      live "/dashboard", DashboardLive, :index
      live "/apis", ApiLive.Index, :index
      live "/apis/new", ApiLive.New, :new
      live "/apis/:id", ApiLive.Show, :show
      live "/apis/:id/analytics", ApiLive.Analytics, :analytics
      live "/flows", FlowLive.Index, :index
      live "/api-keys", ApiKeyLive.Index, :index
      live "/api-keys/:id", ApiKeyLive.Show, :show
      live "/billing", BillingLive.Plans, :index
      live "/billing/manage", BillingLive.Manage, :manage
      live "/settings", SettingsLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    live_session :editor,
      layout: {BlackboexWeb.Layouts, :editor},
      on_mount: [
        {BlackboexWeb.UserAuth, :require_authenticated},
        {BlackboexWeb.Hooks.SetOrganization, :default}
      ] do
      live "/apis/:id/edit", ApiLive.Edit.RedirectLive
      live "/apis/:id/edit/chat", ApiLive.Edit.ChatLive
      live "/apis/:id/edit/validation", ApiLive.Edit.ValidationLive
      live "/apis/:id/edit/run", ApiLive.Edit.RunLive
      live "/apis/:id/edit/metrics", ApiLive.Edit.MetricsLive
      live "/apis/:id/edit/publish", ApiLive.Edit.PublishLive
      live "/apis/:id/edit/info", ApiLive.Edit.InfoLive
      live "/flows/:id/edit", FlowLive.Edit, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", BlackboexWeb do
    pipe_through [:browser]

    live_session :current_user,
      layout: {BlackboexWeb.Layouts, :auth},
      on_mount: [{BlackboexWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
