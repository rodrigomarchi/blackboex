defmodule BlackboexWeb.ApiLive.Show do
  @moduledoc """
  LiveView for viewing an API's details, metrics, and testing.
  Organized in tabs: Overview, Metrics, Test.
  """

  use BlackboexWeb, :live_view

  import Ecto.Query

  require Logger

  alias Blackboex.Apis
  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.MetricRollup
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Repo
  alias Blackboex.Testing.RequestExecutor

  @periods %{"24h" => 1, "7d" => 7, "30d" => 30}

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    org = resolve_organization(socket, params)

    case org && Apis.get_api(org.id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "API not found")
         |> push_navigate(to: ~p"/apis")}

      api ->
        {:ok,
         assign(socket,
           api: api,
           org: org,
           page_title: api.name,
           tab: "overview",
           # Compile
           compile_errors: nil,
           compiling: false,
           # Metrics
           period: "7d",
           metrics_loaded: false,
           invocation_data: [],
           latency_data: [],
           error_data: [],
           total_invocations: 0,
           total_errors: 0,
           error_rate: 0.0,
           avg_latency: 0,
           # Test
           test_method: api.method || "GET",
           test_url: "/api/#{org.slug}/#{api.slug}",
           test_body_json: default_test_body(api),
           test_body_error: nil,
           test_api_key: "",
           test_response: nil,
           test_loading: false,
           test_error: nil,
           test_ref: nil,
           request_tab: "body",
           response_tab: "body"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <div>
          <div class="flex items-center gap-3">
            <h1 class="text-2xl font-bold tracking-tight">{@api.name}</h1>
            <span class={[
              "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold",
              status_color(@api.status)
            ]}>
              {@api.status}
            </span>
          </div>
          <p :if={@api.description} class="text-muted-foreground mt-1">{@api.description}</p>
        </div>
        <div class="flex items-center gap-3">
          <.link
            :if={@api.status == "published" and @api.visibility == "public"}
            href={"/api/#{@org.slug}/#{@api.slug}/docs"}
            target="_blank"
            class="inline-flex items-center gap-1 rounded-md border px-3 py-1.5 text-sm font-medium hover:bg-base-200"
          >
            <.icon name="hero-document-text" class="size-4" /> OpenAPI
          </.link>
          <.link
            :if={@api.status in ["compiled", "published"]}
            navigate={~p"/apis/#{@api.id}/analytics"}
            class="inline-flex items-center gap-1 rounded-md border px-3 py-1.5 text-sm font-medium hover:bg-base-200"
          >
            <.icon name="hero-chart-bar" class="size-4" /> Analytics
          </.link>
          <.link
            navigate={~p"/apis/#{@api.id}/edit"}
            class="inline-flex items-center rounded-md bg-primary px-3 py-1.5 text-sm font-medium text-primary-foreground hover:bg-primary/90"
          >
            <.icon name="hero-pencil-square" class="size-4 mr-1" /> Edit
          </.link>
          <.link
            navigate={~p"/apis"}
            class="text-sm text-muted-foreground hover:text-foreground"
          >
            Back to APIs
          </.link>
        </div>
      </div>

      <%!-- Tabs --%>
      <div class="border-b">
        <div class="flex gap-0">
          <button
            :for={t <- ~w(overview metrics test)}
            phx-click="switch_tab"
            phx-value-tab={t}
            class={[
              "px-4 py-2 text-sm font-medium border-b-2 transition-colors",
              if(t == @tab,
                do: "border-primary text-primary",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            {tab_label(t)}
          </button>
        </div>
      </div>

      <%!-- Tab Content --%>
      {render_tab(assigns)}
    </div>
    """
  end

  # ── Overview Tab ─────────────────────────────────────────────────────

  defp render_tab(%{tab: "overview"} = assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- API Info Card --%>
      <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <span class="text-muted-foreground">Slug</span>
            <p class="font-mono font-medium">{@api.slug}</p>
          </div>
          <div>
            <span class="text-muted-foreground">Template</span>
            <p class="font-medium">{@api.template_type}</p>
          </div>
          <div>
            <span class="text-muted-foreground">Method</span>
            <p class="font-medium">{@api.method || "POST"}</p>
          </div>
          <div>
            <span class="text-muted-foreground">Visibility</span>
            <p class="font-medium">{@api.visibility}</p>
          </div>
        </div>

        <%= if @api.status in ["compiled", "published"] do %>
          <div class="mt-4 pt-4 border-t flex items-center gap-2 text-sm">
            <span class="text-muted-foreground">Endpoint:</span>
            <code class="rounded bg-muted px-2 py-1 font-mono">
              /api/{@org.slug}/{@api.slug}
            </code>
            <%= if @api.status == "published" and @api.visibility == "public" do %>
              <a
                href={"/api/#{@org.slug}/#{@api.slug}/docs"}
                target="_blank"
                class="text-primary hover:underline ml-2"
              >
                View OpenAPI docs
              </a>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Source Code --%>
      <%= if @api.source_code do %>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold">Source Code</h2>
            <button
              phx-click="compile"
              disabled={@compiling}
              class="inline-flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
            >
              {if @compiling, do: "Compiling...", else: "Compile"}
            </button>
          </div>
          <pre class="overflow-x-auto rounded-md bg-muted p-4 text-sm"><code>{@api.source_code}</code></pre>
        </div>
      <% end %>

      <%!-- Compile Errors --%>
      <%= if @compile_errors do %>
        <div class="rounded-lg border border-destructive bg-destructive/10 p-4 text-sm text-destructive space-y-1">
          <p class="font-semibold">Compilation failed:</p>
          <ul class="list-disc list-inside">
            <%= for error <- @compile_errors do %>
              <li>{error}</li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Metrics Tab ──────────────────────────────────────────────────────

  defp render_tab(%{tab: "metrics"} = assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Period Selector --%>
      <div class="flex justify-end gap-2">
        <button
          :for={period <- ["24h", "7d", "30d"]}
          phx-click="change_period"
          phx-value-period={period}
          class={[
            "px-3 py-1 rounded-md text-sm font-medium",
            if(@period == period,
              do: "bg-primary text-primary-foreground",
              else: "bg-muted text-muted-foreground hover:bg-base-200"
            )
          ]}
        >
          {period}
        </button>
      </div>

      <%!-- Stat Cards --%>
      <div class="grid grid-cols-4 gap-4">
        <div class="rounded-lg border bg-card p-4 text-card-foreground shadow-sm">
          <p class="text-sm text-muted-foreground">Invocations</p>
          <p class="text-2xl font-bold">{@total_invocations}</p>
        </div>
        <div class="rounded-lg border bg-card p-4 text-card-foreground shadow-sm">
          <p class="text-sm text-muted-foreground">Errors</p>
          <p class="text-2xl font-bold">{@total_errors}</p>
        </div>
        <div class="rounded-lg border bg-card p-4 text-card-foreground shadow-sm">
          <p class="text-sm text-muted-foreground">Error Rate</p>
          <p class="text-2xl font-bold">{@error_rate}%</p>
        </div>
        <div class="rounded-lg border bg-card p-4 text-card-foreground shadow-sm">
          <p class="text-sm text-muted-foreground">Avg Latency</p>
          <p class="text-2xl font-bold">{@avg_latency}ms</p>
        </div>
      </div>

      <%= if @invocation_data == [] do %>
        <div class="rounded-lg border bg-card p-8 text-center text-muted-foreground shadow-sm">
          <p class="text-lg">No analytics data for this period.</p>
          <p class="text-sm mt-2">
            Data is aggregated hourly. Check back after your API receives traffic.
          </p>
        </div>
      <% else %>
        <div class="grid grid-cols-2 gap-6">
          <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
            <BlackboexWeb.Components.Charts.bar_chart
              data={@invocation_data}
              title="Invocations"
            />
          </div>
          <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
            <BlackboexWeb.Components.Charts.line_chart
              data={@latency_data}
              title="P95 Latency (ms)"
              color="#f59e0b"
            />
          </div>
        </div>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
          <BlackboexWeb.Components.Charts.bar_chart
            data={@error_data}
            title="Errors"
            color="#ef4444"
          />
        </div>
      <% end %>
    </div>
    """
  end

  # ── Test Tab ─────────────────────────────────────────────────────────

  defp render_tab(%{tab: "test"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if @api.status not in ["compiled", "published"] do %>
        <div class="rounded-lg border bg-card p-8 text-center text-muted-foreground shadow-sm">
          <p class="text-lg">API needs to be compiled first.</p>
          <p class="text-sm mt-2">Go to the Overview tab and click Compile.</p>
        </div>
      <% else %>
        <div class="grid grid-cols-2 gap-6">
          <%!-- Request Builder --%>
          <div class="space-y-3">
            <div class="flex items-center gap-2">
              <select
                name="method"
                phx-change="update_method"
                class="rounded-md border bg-background px-2 py-1.5 text-sm font-semibold w-28"
              >
                <option
                  :for={m <- ~w(GET POST PUT PATCH DELETE)}
                  value={m}
                  selected={m == @test_method}
                >
                  {m}
                </option>
              </select>
              <input
                type="text"
                value={@test_url}
                class="flex-1 rounded-md border bg-background px-3 py-1.5 text-sm font-mono"
                readonly
              />
              <button
                phx-click="send_test"
                disabled={@test_loading}
                class="inline-flex items-center rounded-md bg-primary px-4 py-1.5 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
              >
                {if @test_loading, do: "Sending...", else: "Send"}
              </button>
            </div>

            <div class="rounded-lg border bg-card">
              <div class="flex border-b">
                <button
                  :for={tab <- ~w(body auth)}
                  phx-click="switch_req_tab"
                  phx-value-tab={tab}
                  class={[
                    "flex-1 px-3 py-2 text-xs font-medium border-b-2",
                    if(tab == @request_tab,
                      do: "border-primary text-primary",
                      else: "border-transparent text-muted-foreground hover:text-foreground"
                    )
                  ]}
                >
                  {String.capitalize(tab)}
                </button>
              </div>
              <div class="p-3">
                {render_request_content(assigns)}
              </div>
            </div>
          </div>

          <%!-- Response Viewer --%>
          <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
            <div class="flex items-center justify-between border-b px-4 py-2">
              <h3 class="text-sm font-semibold">Response</h3>
              <%= if @test_response do %>
                <div class="flex items-center gap-2">
                  <span class={[
                    "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
                    resp_status_color(@test_response.status)
                  ]}>
                    {@test_response.status}
                  </span>
                  <span class="text-xs text-muted-foreground">{@test_response.duration_ms}ms</span>
                </div>
              <% end %>
            </div>
            <div class="p-4">
              <%= cond do %>
                <% @test_loading -> %>
                  <div class="flex items-center justify-center py-8">
                    <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-primary" />
                  </div>
                <% @test_error -> %>
                  <div class="rounded border border-destructive bg-destructive/10 p-3 text-xs text-destructive">
                    {@test_error}
                  </div>
                <% @test_response -> %>
                  <div class="space-y-3">
                    <div class="flex border-b">
                      <button
                        :for={tab <- ~w(body headers)}
                        phx-click="switch_resp_tab"
                        phx-value-tab={tab}
                        class={[
                          "flex-1 px-3 py-2 text-xs font-medium border-b-2",
                          if(tab == @response_tab,
                            do: "border-primary text-primary",
                            else: "border-transparent text-muted-foreground hover:text-foreground"
                          )
                        ]}
                      >
                        {String.capitalize(tab)}
                      </button>
                    </div>
                    {render_response_content(assigns)}
                  </div>
                <% true -> %>
                  <p class="text-sm text-muted-foreground text-center py-8">
                    Send a request to see the response
                  </p>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_request_content(%{request_tab: "body"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <textarea
        name="test_body_json"
        rows="8"
        phx-change="update_body"
        class={[
          "w-full rounded-md border bg-background px-2 py-1 text-xs font-mono",
          if(@test_body_error, do: "border-destructive", else: "")
        ]}
        placeholder="{}"
      >{@test_body_json}</textarea>
      <p :if={@test_body_error} class="text-xs text-destructive">{@test_body_error}</p>
    </div>
    """
  end

  defp render_request_content(%{request_tab: "auth"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <label class="text-xs text-muted-foreground">API Key</label>
      <input
        type="text"
        name="test_api_key"
        value={@test_api_key}
        phx-change="update_api_key"
        placeholder="Enter API key"
        class="w-full rounded-md border bg-background px-2 py-1 text-xs font-mono"
      />
      <p class="text-xs text-muted-foreground">Sent as X-Api-Key header</p>
    </div>
    """
  end

  defp render_response_content(%{response_tab: "body"} = assigns) do
    ~H"""
    <pre class="overflow-x-auto rounded bg-muted p-3 text-xs font-mono max-h-80 overflow-y-auto"><code>{format_body(@test_response.body)}</code></pre>
    """
  end

  defp render_response_content(%{response_tab: "headers"} = assigns) do
    ~H"""
    <div class="space-y-1">
      <div :for={{key, value} <- @test_response.headers} class="flex gap-2 text-xs">
        <span class="font-semibold text-muted-foreground min-w-[120px]">{key}</span>
        <span class="font-mono">{value}</span>
      </div>
    </div>
    """
  end

  # ── Events ───────────────────────────────────────────────────────────

  @valid_tabs ~w(overview metrics test)

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @valid_tabs do
    socket = assign(socket, tab: tab)

    socket =
      if tab == "metrics" and not socket.assigns.metrics_loaded,
        do: load_metrics(socket),
        else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket)
      when is_map_key(@periods, period) do
    {:noreply,
     socket
     |> assign(period: period)
     |> load_metrics()}
  end

  @impl true
  def handle_event("compile", _params, socket) do
    api = socket.assigns.api
    org = socket.assigns.org

    case Compiler.compile(api, api.source_code) do
      {:ok, module} ->
        {:ok, updated_api} = Apis.update_api(api, %{status: "compiled"})
        Registry.register(api.id, module, org_slug: org.slug, slug: api.slug)

        {:noreply, assign(socket, api: updated_api, compile_errors: nil, compiling: false)}

      {:error, {:validation, reasons}} ->
        {:noreply, assign(socket, compile_errors: reasons, compiling: false)}

      {:error, {:compilation, reason}} ->
        {:noreply, assign(socket, compile_errors: [reason], compiling: false)}
    end
  end

  # Test events

  @valid_methods ~w(GET POST PUT PATCH DELETE)

  @impl true
  def handle_event("update_method", %{"method" => method}, socket)
      when method in @valid_methods do
    {:noreply, assign(socket, test_method: method)}
  end

  @impl true
  def handle_event("update_body", %{"test_body_json" => body}, socket) do
    error =
      case Jason.decode(body) do
        {:ok, _} -> nil
        {:error, _} -> "Invalid JSON"
      end

    {:noreply, assign(socket, test_body_json: body, test_body_error: error)}
  end

  @impl true
  def handle_event("update_api_key", %{"test_api_key" => key}, socket) do
    {:noreply, assign(socket, test_api_key: key)}
  end

  @impl true
  def handle_event("switch_req_tab", %{"tab" => tab}, socket) when tab in ~w(body auth) do
    {:noreply, assign(socket, request_tab: tab)}
  end

  @impl true
  def handle_event("switch_resp_tab", %{"tab" => tab}, socket) when tab in ~w(body headers) do
    {:noreply, assign(socket, response_tab: tab)}
  end

  @impl true
  def handle_event("send_test", _params, %{assigns: %{test_loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("send_test", _params, socket) do
    method = socket.assigns.test_method |> String.downcase() |> String.to_existing_atom()

    headers = [{"content-type", "application/json"}]

    headers =
      if socket.assigns.test_api_key != "" do
        headers ++ [{"x-api-key", socket.assigns.test_api_key}]
      else
        headers
      end

    body = if method in [:post, :put, :patch], do: socket.assigns.test_body_json, else: nil

    request = %{method: method, url: socket.assigns.test_url, headers: headers, body: body}

    task =
      Task.async(fn ->
        RequestExecutor.execute(request, plug: BlackboexWeb.Endpoint)
      end)

    {:noreply, assign(socket, test_loading: true, test_error: nil, test_ref: task.ref)}
  end

  @impl true
  def handle_info({ref, result}, %{assigns: %{test_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, response} ->
        {:noreply,
         assign(socket,
           test_response: response,
           test_loading: false,
           test_error: nil,
           test_ref: nil,
           response_tab: "body"
         )}

      {:error, :forbidden} ->
        {:noreply,
         assign(socket, test_loading: false, test_ref: nil, test_error: "URL not allowed.")}

      {:error, :timeout} ->
        {:noreply,
         assign(socket, test_loading: false, test_ref: nil, test_error: "Request timed out.")}

      {:error, reason} ->
        Logger.warning("Show test request failed: #{inspect(reason)}")

        {:noreply,
         assign(socket, test_loading: false, test_ref: nil, test_error: "Connection error.")}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{test_ref: ref}} = socket) do
    {:noreply, assign(socket, test_loading: false, test_ref: nil)}
  end

  # ── Private Helpers ──────────────────────────────────────────────────

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
          p95: entries |> Enum.map(& &1.p95_duration_ms) |> Enum.max(fn -> 0.0 end),
          avg_dur: entries |> Enum.map(& &1.avg_duration_ms) |> average()
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

    avg_latency = Analytics.avg_latency(api_id, period: period_to_atom(socket.assigns.period))

    assign(socket,
      invocation_data: invocation_data,
      latency_data: latency_data,
      error_data: error_data,
      total_invocations: total_invocations,
      total_errors: total_errors,
      error_rate: error_rate,
      avg_latency: avg_latency,
      metrics_loaded: true
    )
  rescue
    error ->
      Logger.error("Failed to load show metrics: #{Exception.message(error)}")

      assign(socket,
        invocation_data: [],
        latency_data: [],
        error_data: [],
        total_invocations: 0,
        total_errors: 0,
        error_rate: 0.0,
        avg_latency: 0,
        metrics_loaded: true
      )
  end

  defp average([]), do: 0.0
  defp average(list), do: Enum.sum(list) / length(list)

  defp period_to_atom("24h"), do: :day
  defp period_to_atom("7d"), do: :week
  defp period_to_atom("30d"), do: :month

  defp resolve_organization(socket, params) do
    scope = socket.assigns.current_scope

    case params["org"] do
      nil ->
        scope.organization

      org_id ->
        org = Blackboex.Organizations.get_organization(org_id)
        if org && Blackboex.Organizations.get_user_membership(org, scope.user), do: org
    end
  end

  defp default_test_body(api) do
    if api.example_request,
      do: Jason.encode!(api.example_request, pretty: true),
      else: ~s|{"n": 5}|
  end

  defp format_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> body
    end
  end

  defp format_body(body), do: inspect(body)

  defp tab_label("overview"), do: "Overview"
  defp tab_label("metrics"), do: "Metrics"
  defp tab_label("test"), do: "Test"

  defp status_color("draft"), do: "border bg-muted text-muted-foreground"
  defp status_color("compiled"), do: "border-green-500 bg-green-50 text-green-700"
  defp status_color("published"), do: "border-blue-500 bg-blue-50 text-blue-700"
  defp status_color("archived"), do: "border-gray-500 bg-gray-50 text-gray-500"
  defp status_color(_), do: "border bg-muted text-muted-foreground"

  defp resp_status_color(status) when status >= 200 and status < 300,
    do: "border-green-500 bg-green-50 text-green-700"

  defp resp_status_color(status) when status >= 400 and status < 500,
    do: "border-yellow-500 bg-yellow-50 text-yellow-700"

  defp resp_status_color(status) when status >= 500,
    do: "border-red-500 bg-red-50 text-red-700"

  defp resp_status_color(_), do: "border bg-muted text-muted-foreground"
end
