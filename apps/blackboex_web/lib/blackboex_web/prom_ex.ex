defmodule BlackboexWeb.PromEx do
  @moduledoc """
  PromEx configuration for BlackBoex.

  Configures built-in plugins (BEAM, Phoenix, Ecto, Oban) and custom
  plugins for API invocation and LLM metrics.
  """

  use PromEx, otp_app: :blackboex_web

  alias BlackboexWeb.PromEx.Plugins.ApiMetrics
  alias BlackboexWeb.PromEx.Plugins.LlmMetrics

  @impl true
  def plugins do
    base = [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: BlackboexWeb.Router, endpoint: BlackboexWeb.Endpoint},
      {PromEx.Plugins.Ecto, repos: [Blackboex.Repo]},
      ApiMetrics,
      LlmMetrics
    ]

    # The Oban plugin polls the Repo from a TelemetryPoller process that has no
    # Ecto sandbox checkout in tests, producing DBConnection.OwnershipError
    # noise. Skip it when explicitly disabled via config (set in test.exs).
    prom_ex_config = Application.get_env(:blackboex_web, __MODULE__, [])

    if Keyword.get(prom_ex_config, :skip_oban_plugin, false) do
      base
    else
      base ++ [{PromEx.Plugins.Oban, oban_supervisors: [Oban]}]
    end
  end

  @impl true
  def dashboards do
    []
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end
end
