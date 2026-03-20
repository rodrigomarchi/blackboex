defmodule BlackboexWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # OpenTelemetry instrumentation MUST be set up before the supervision tree starts
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:blackboex, :repo], db_statement: :enabled)
    :ok = OpentelemetryLoggerMetadata.setup()

    children = [
      BlackboexWeb.PromEx,
      BlackboexWeb.Telemetry,
      {BlackboexWeb.RateLimiterBackend, clean_period: :timer.minutes(10)},
      # Start to serve requests, typically the last entry
      BlackboexWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BlackboexWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BlackboexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
