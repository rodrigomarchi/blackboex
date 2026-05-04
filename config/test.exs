import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :blackboex, Blackboex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5435,
  database: "blackboex_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :blackboex_web, BlackboexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BoLPtjJ7P6fNgjv2yYPoouWOByN6TgaHGYOlN0mmdlCnLituqdrCUMSz10MHKeIX",
  server: false

# Use test adapter for Swoosh mailer
config :blackboex, Blackboex.Mailer, adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Use mock LLM client in tests
config :blackboex, :llm_client, Blackboex.LLM.ClientMock

# Oban: manual testing mode (jobs don't auto-execute)
config :blackboex, Oban, testing: :manual

# FunWithFlags: disable ETS cache in tests for determinism
config :fun_with_flags, :cache, enabled: false

# PromEx: keep enabled (the /metrics endpoint smoke test needs it), but skip
# the Oban plugin in tests. Its TelemetryPoller queries the Repo from a process
# without a sandbox checkout, producing DBConnection.OwnershipError noise on
# every poll. Metrics aren't scraped in tests so we lose nothing.
config :blackboex_web, BlackboexWeb.PromEx,
  skip_oban_plugin: true,
  drop_metrics_groups: [
    :oban_init_event_metrics,
    :oban_job_event_metrics,
    :oban_queue_polling_event_metrics
  ]

# OpenTelemetry: disable export in tests
config :opentelemetry, traces_exporter: :none

# Flow executor: run steps synchronously in tests so Ecto sandbox ownership
# is respected (async steps run in separate processes without sandbox access).
config :blackboex, :flow_executor_async, false

# Registry: shorten the shutdown drain so the shutdown lifecycle tests don't
# burn ~30s each waiting for unrelated sandbox tasks to finish.
config :blackboex, Blackboex.Apis.Registry,
  drain_timeout_ms: 200,
  drain_poll_ms: 25

# Playgrounds.Executor: shorten the sandbox execution timeout so the timeout
# happy-path test doesn't sit idle for 15 seconds.
config :blackboex, Blackboex.Playgrounds.Executor, timeout_ms: 50

# Sample workspaces are expensive to materialize and most tests only need the
# default project/membership. Tests that exercise sample sync pass
# `materialize: true` explicitly.
config :blackboex, Blackboex.Projects.Samples, materialize_by_default: false
