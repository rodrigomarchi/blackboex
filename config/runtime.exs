import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Start the Phoenix endpoint server when PHX_SERVER=true (used by releases/Docker)
if System.get_env("PHX_SERVER") do
  config :blackboex_web, BlackboexWeb.Endpoint, server: true
end

config :blackboex_web, BlackboexWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Stripe configuration (all environments — loaded from env vars when present)
if stripe_key = System.get_env("STRIPE_SECRET_KEY") do
  config :stripity_stripe, api_key: stripe_key
end

if stripe_webhook_secret = System.get_env("STRIPE_WEBHOOK_SECRET") do
  config :blackboex, :stripe_webhook_secret, stripe_webhook_secret
end

# ReqLLM API keys (all environments — loaded from env vars when present)
config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY")

# Structured JSON logging in production
if config_env() == :prod do
  config :logger, :default_handler, formatter: {LoggerJSON.Formatters.Basic, []}

  config :phoenix, :logger, false
end

# OpenTelemetry configuration
if config_env() == :prod do
  config :opentelemetry,
    resource: %{
      "service.name" => "blackboex",
      "deployment.environment" => "production"
    },
    span_processor: :batch,
    traces_exporter: :otlp,
    sampler: {:parent_based, %{root: {:trace_id_ratio_based, 0.1}}}

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :blackboex, Blackboex.Repo,
    ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :blackboex_web, BlackboexWeb.Endpoint,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :blackboex, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Stripe keys — required in production
  config :stripity_stripe,
    api_key:
      System.get_env("STRIPE_SECRET_KEY") ||
        raise("missing STRIPE_SECRET_KEY env var")

  config :blackboex,
         :stripe_webhook_secret,
         System.get_env("STRIPE_WEBHOOK_SECRET") ||
           raise("missing STRIPE_WEBHOOK_SECRET env var")

  # Use real LLM client in production
  config :blackboex, :llm_client, Blackboex.LLM.ReqLLMClient

  # Swoosh mailer - requires SMTP or API-based adapter in production.
  # Override with env vars for your provider (e.g., Postmark, SendGrid, AWS SES).
  config :blackboex, Blackboex.Mailer,
    adapter: Swoosh.Adapters.Postmark,
    api_key: System.get_env("MAILER_API_KEY") || raise("missing MAILER_API_KEY env var")
end
