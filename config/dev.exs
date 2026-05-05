import Config

# Configure your database
config :blackboex, Blackboex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5434,
  database: "blackboex_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "10"))

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :blackboex_web, BlackboexWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: System.get_env("DISABLE_CODE_RELOAD") != "true",
  debug_errors: true,
  secret_key_base: "1R2CsayqIa9hKa7syZAcBkUB84/JNZSaEuiRiRoU4prFcgzKfvo+bq2L+VrG61ef",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:blackboex_web, ~w(--sourcemap=inline --watch)]},
    esbuild_admin:
      {Esbuild, :install_and_run, [:blackboex_admin, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:blackboex_web, ~w(--watch)]},
    tailwind_admin: {Tailwind, :install_and_run, [:blackboex_admin, ~w(--watch)]}
  ]

# Reload browser tabs when matching files change.
config :blackboex_web, BlackboexWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      # Static assets, except user uploads
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      # Gettext translations
      ~r"priv/gettext/.*\.po$"E,
      # Router, Controllers, LiveViews and LiveComponents
      ~r"lib/blackboex_web/router\.ex$"E,
      ~r"lib/blackboex_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :blackboex_web, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# SaladUI components path
config :salad_ui,
  components_path: Path.join(File.cwd!(), "apps/blackboex_web/lib/blackboex_web/components/ui")

# Use real LLM client in dev
config :blackboex, :llm_client, Blackboex.LLM.ReqLLMClient

# Feature flags (default ON in dev — see `Blackboex.Features`)
config :blackboex, :features, project_agent: true

# OpenTelemetry: disable export in dev (no collector running by default)
config :opentelemetry, traces_exporter: :none
