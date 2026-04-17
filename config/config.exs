# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :blackboex, :scopes,
  user: [
    default: true,
    module: Blackboex.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Blackboex.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

# Configure Mix tasks and generators
config :blackboex,
  ecto_repos: [Blackboex.Repo]

config :blackboex_web,
  ecto_repos: [Blackboex.Repo],
  generators: [context_app: :blackboex]

# Configures the endpoint
config :blackboex_web, BlackboexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BlackboexWeb.ErrorHTML, json: BlackboexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Blackboex.PubSub,
  live_view: [signing_salt: "EulPwe/e"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  blackboex_web: [
    args:
      ~w(js/app.js js/editor_tiptap.js js/editor_code.js js/editor_flow.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --external:mermaid --alias:@=. --log-override:equals-new-object=silent),
    cd: Path.expand("../apps/blackboex_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  blackboex_admin: [
    args:
      ~w(js/admin.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/blackboex_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.2.2",
  blackboex_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/blackboex_web", __DIR__)
  ],
  blackboex_admin: [
    args: ~w(
      --input=assets/css/admin.css
      --output=priv/static/assets/css/admin.css
    ),
    cd: Path.expand("../apps/blackboex_web", __DIR__)
  ]

# Backpex admin panel
config :backpex,
  pubsub_server: Blackboex.PubSub,
  translator_function: {BlackboexWeb.Components.Helpers, :translate_backpex},
  error_translator_function: {BlackboexWeb.Components.Helpers, :translate_error}

# ExAudit row-level audit tracking
config :ex_audit,
  ecto_repos: [Blackboex.Repo],
  version_schema: Blackboex.Audit.Version,
  tracked_schemas: [
    Blackboex.Billing.Subscription,
    Blackboex.Apis.Api,
    Blackboex.Apis.ApiKey,
    Blackboex.Organizations.Organization
  ]

# Playground API self-call base URL (override via PLAYGROUND_BASE_URL in prod)
config :blackboex, Blackboex.Playgrounds.Api, base_url: "http://localhost:4000"

# Stripe client configuration
config :blackboex, :stripe_client, Blackboex.Billing.StripeClient.Live

# FunWithFlags feature flag configuration
config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Blackboex.Repo

config :fun_with_flags, :cache_bust_notifications,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Blackboex.PubSub

# Oban job processing
config :blackboex, Oban,
  repo: Blackboex.Repo,
  queues: [billing: 10, analytics: 5, generation: 3, flows: 5, playground_agent: 5],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", Blackboex.Apis.MetricRollupWorker},
       {"*/2 * * * *", Blackboex.Agent.RecoveryWorker}
     ]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id, :api_id, :user_id]

# PromEx metrics
config :blackboex_web, BlackboexWeb.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: []

# SaladUI configuration
config :salad_ui,
  web_module: BlackboexWeb,
  component_module_prefix: "BlackboexWeb.Components"

# Swoosh mailer configuration
config :blackboex, Blackboex.Mailer, adapter: Swoosh.Adapters.Local

# Disable Swoosh API client (not needed for Local/Test adapters)
config :swoosh, :api_client, false

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
