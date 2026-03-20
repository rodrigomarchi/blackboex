defmodule BlackboexWeb.ApiLive.Analytics do
  @moduledoc """
  LiveView for per-API analytics with SVG charts.
  Displays invocations, latency, and error metrics over time.
  """

  use BlackboexWeb, :live_view

  import Ecto.Query

  alias Blackboex.Apis
  alias Blackboex.Apis.MetricRollup
  alias Blackboex.Repo

  require Logger

  @periods %{
    "24h" => 1,
    "7d" => 7,
    "30d" => 30
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = socket.assigns.current_scope.organization

    case org && Apis.get_api(org.id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "API not found")
         |> push_navigate(to: ~p"/apis")}

      api ->
        {:ok,
         socket
         |> assign(api: api, org: org, page_title: "Analytics - #{api.name}", period: "7d")
         |> load_metrics()}
    end
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket)
      when is_map_key(@periods, period) do
    {:noreply,
     socket
     |> assign(period: period)
     |> load_metrics()}
  end

  @spec load_metrics(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_metrics(socket) do
    api_id = socket.assigns.api.id
    days = Map.fetch!(@periods, socket.assigns.period)
    start_date = Date.add(Date.utc_today(), -days)

    rollups =
      from(r in MetricRollup,
        where: r.api_id == ^api_id and r.date >= ^start_date,
        order_by: [asc: r.date, asc: r.hour]
      )
      |> Repo.all()

    daily =
      rollups
      |> Enum.group_by(& &1.date)
      |> Enum.sort_by(fn {date, _} -> date end)
      |> Enum.map(fn {date, entries} ->
        %{
          label: Calendar.strftime(date, "%m/%d"),
          invocations: Enum.sum(Enum.map(entries, & &1.invocations)),
          errors: Enum.sum(Enum.map(entries, & &1.errors)),
          p95: entries |> Enum.map(& &1.p95_duration_ms) |> Enum.max(fn -> 0.0 end)
        }
      end)

    invocation_data = Enum.map(daily, &%{label: &1.label, value: &1.invocations})
    latency_data = Enum.map(daily, &%{label: &1.label, value: round(&1.p95)})
    error_data = Enum.map(daily, &%{label: &1.label, value: &1.errors})

    total_invocations = Enum.sum(Enum.map(daily, & &1.invocations))
    total_errors = Enum.sum(Enum.map(daily, & &1.errors))

    error_rate =
      if total_invocations > 0,
        do: Float.round(total_errors / total_invocations * 100, 1),
        else: 0.0

    assign(socket,
      invocation_data: invocation_data,
      latency_data: latency_data,
      error_data: error_data,
      total_invocations: total_invocations,
      total_errors: total_errors,
      error_rate: error_rate
    )
  rescue
    error ->
      Logger.error("Failed to load analytics metrics: #{Exception.message(error)}")

      assign(socket,
        invocation_data: [],
        latency_data: [],
        error_data: [],
        total_invocations: 0,
        total_errors: 0,
        error_rate: 0.0
      )
  end
end
