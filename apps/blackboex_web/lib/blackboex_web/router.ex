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
    plug BlackboexWeb.Plugs.RequireSetup
    plug BlackboexWeb.Plugs.EditorBundle
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

  pipeline :set_organization_from_url do
    plug BlackboexWeb.Plugs.SetOrganizationFromUrl
  end

  pipeline :set_project_from_url do
    plug BlackboexWeb.Plugs.SetProjectFromUrl
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
    get "/:org_slug/:project_slug/:api_slug", PublicApiController, :show_project
    get "/:org_slug/:api_slug", PublicApiController, :show
  end

  # Flow webhook — public, no auth, no CSRF
  scope "/webhook", BlackboexWeb do
    pipe_through :api
    post "/:token", FlowWebhookController, :execute
    post "/:token/resume/:event_type", FlowWebhookController, :resume
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

    scope "/showcase", BlackboexWeb do
      pipe_through :browser

      live_session :showcase, layout: {BlackboexWeb.Layouts, :showcase} do
        live "/", ShowcaseLive, :index
        live "/:section", ShowcaseLive, :show
      end
    end
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
      # API data
      live_resources "/api-keys", ApiKeyLive
      live_resources "/api-versions", ApiVersionLive
      live_resources "/agent-conversations", AgentConversationLive
      live_resources "/agent-runs", AgentRunLive
      live_resources "/agent-events", AgentEventLive
      live_resources "/data-store-entries", DataStoreEntryLive
      live_resources "/invocation-logs", InvocationLogLive
      live_resources "/metric-rollups", MetricRollupLive

      # Projects
      live_resources "/projects", ProjectLive
      live_resources "/project-memberships", ProjectMembershipLive

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

  ## Org-scoped routes: /orgs/:org_slug/...

  scope "/orgs/:org_slug", BlackboexWeb do
    pipe_through [
      :browser,
      :require_authenticated_user,
      :set_organization_from_url,
      :audit_context
    ]

    live_session :org_scoped,
      layout: {BlackboexWeb.Layouts, :app},
      on_mount: [
        {BlackboexWeb.UserAuth, :require_authenticated},
        {BlackboexWeb.Hooks.SetOrganizationFromUrl, :default},
        {BlackboexWeb.Hooks.SetPreferredProject, :default},
        {BlackboexWeb.Hooks.TrackCurrentPath, :default},
        {BlackboexWeb.Hooks.TrackLastVisited, :default}
      ] do
      live "/settings", OrgSettingsLive, :dashboard
      live "/settings/apis", OrgSettingsLive, :apis
      live "/settings/flows", OrgSettingsLive, :flows
      live "/settings/llm", OrgSettingsLive, :llm
      live "/settings/general", OrgSettingsLive, :general
      live "/members", OrgMemberLive.Index, :index
      live "/projects", ProjectLive.Index, :index
      live "/projects/new", ProjectLive.New, :new
    end
  end

  ## Project-scoped routes: /orgs/:org_slug/projects/:project_slug/...

  scope "/orgs/:org_slug/projects/:project_slug", BlackboexWeb do
    pipe_through [
      :browser,
      :require_authenticated_user,
      :set_organization_from_url,
      :set_project_from_url,
      :audit_context
    ]

    live_session :project_scoped,
      layout: {BlackboexWeb.Layouts, :app},
      on_mount: [
        {BlackboexWeb.UserAuth, :require_authenticated},
        {BlackboexWeb.Hooks.SetOrganizationFromUrl, :default},
        {BlackboexWeb.Hooks.SetProjectFromUrl, :default},
        {BlackboexWeb.Hooks.TrackCurrentPath, :default},
        {BlackboexWeb.Hooks.TrackLastVisited, :default}
      ] do
      live "/", ProjectSettingsLive, :dashboard
      live "/settings", ProjectSettingsLive, :dashboard
      live "/settings/apis", ProjectSettingsLive, :apis
      live "/settings/flows", ProjectSettingsLive, :flows
      live "/settings/llm", ProjectSettingsLive, :llm
      live "/settings/general", ProjectSettingsLive, :general
      live "/apis", ApiLive.Index, :index
      live "/apis/new", ApiLive.New, :new
      live "/apis/:api_slug", ApiLive.Show, :show
      live "/apis/:api_slug/analytics", ApiLive.Analytics, :analytics
      live "/flows", FlowLive.Index, :index
      live "/pages", PageLive.Index, :index
      live "/playgrounds", PlaygroundLive.Index, :index
      live "/api-keys", ProjectLive.ApiKeys, :index
      live "/api-keys/:id", ProjectLive.ApiKeyShow, :show
      live "/env-vars", ProjectLive.EnvVars, :index
      live "/integrations", ProjectLive.LlmIntegrations, :index
      live "/members", ProjectMemberLive.Index, :index
    end

    live_session :project_editor,
      layout: {BlackboexWeb.Layouts, :editor},
      on_mount: [
        {BlackboexWeb.UserAuth, :require_authenticated},
        {BlackboexWeb.Hooks.SetOrganizationFromUrl, :default},
        {BlackboexWeb.Hooks.SetProjectFromUrl, :default},
        {BlackboexWeb.Hooks.TrackCurrentPath, :default},
        {BlackboexWeb.Hooks.TrackLastVisited, :default}
      ] do
      live "/apis/:api_slug/edit", ApiLive.Edit.RedirectLive
      live "/apis/:api_slug/edit/chat", ApiLive.Edit.ChatLive
      live "/apis/:api_slug/edit/validation", ApiLive.Edit.ValidationLive
      live "/apis/:api_slug/edit/run", ApiLive.Edit.RunLive
      live "/apis/:api_slug/edit/metrics", ApiLive.Edit.MetricsLive
      live "/apis/:api_slug/edit/publish", ApiLive.Edit.PublishLive
      live "/apis/:api_slug/edit/info", ApiLive.Edit.InfoLive
      live "/pages/:page_slug/edit", PageLive.Edit, :edit
      live "/playgrounds/:playground_slug/edit", PlaygroundLive.Edit, :edit
      live "/flows/:id/edit", FlowLive.Edit, :edit
    end
  end

  ## Authentication routes

  scope "/", BlackboexWeb do
    pipe_through [:browser, :require_authenticated_user, :audit_context]

    live_session :require_authenticated_user,
      layout: {BlackboexWeb.Layouts, :app},
      on_mount: [
        {BlackboexWeb.UserAuth, :require_authenticated},
        {BlackboexWeb.Hooks.SetOrganization, :default},
        {BlackboexWeb.Hooks.TrackCurrentPath, :default}
      ] do
      live "/apis", ApiLive.Index, :index
      live "/apis/new", ApiLive.New, :new
      live "/apis/:id", ApiLive.Show, :show
      live "/apis/:id/analytics", ApiLive.Analytics, :analytics
      live "/flows", FlowLive.Index, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    live_session :editor,
      layout: {BlackboexWeb.Layouts, :editor},
      on_mount: [
        {BlackboexWeb.UserAuth, :require_authenticated},
        {BlackboexWeb.Hooks.SetOrganization, :default},
        {BlackboexWeb.Hooks.TrackCurrentPath, :default}
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
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/invitations/:token", InvitationLive.Accept, :show
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  ## First-run setup wizard

  scope "/setup", BlackboexWeb do
    pipe_through :browser

    live_session :setup,
      layout: {BlackboexWeb.Layouts, :auth},
      on_mount: [{BlackboexWeb.UserAuth, :mount_current_scope}] do
      live "/", SetupLive, :wizard
    end

    get "/finish", SetupController, :finish
  end
end
