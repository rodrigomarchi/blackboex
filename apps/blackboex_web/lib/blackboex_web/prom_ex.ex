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
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: BlackboexWeb.Router, endpoint: BlackboexWeb.Endpoint},
      {PromEx.Plugins.Ecto, repos: [Blackboex.Repo]},
      {PromEx.Plugins.Oban, oban_supervisors: [Oban]},
      ApiMetrics,
      LlmMetrics
    ]
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
