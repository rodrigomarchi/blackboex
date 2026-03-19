defmodule BlackboexWeb.Components.ResponseViewer do
  @moduledoc """
  LiveComponent for displaying API test responses.
  Shows status badge, duration, formatted body, and headers.
  """

  use BlackboexWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-lg border bg-card text-card-foreground shadow-sm" id="response-viewer">
      <div class="flex items-center justify-between border-b px-4 py-2">
        <h3 class="text-sm font-semibold">Response</h3>
        <%= if @response do %>
          <div class="flex items-center gap-2">
            <span class={[
              "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
              status_color(@response.status)
            ]}>
              {@response.status}
            </span>
            <span class="text-xs text-muted-foreground">
              {@response.duration_ms}ms
            </span>
            <%= if @violations != [] do %>
              <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold border-orange-500 bg-orange-50 text-orange-700">
                {length(@violations)} violation(s)
              </span>
            <% else %>
              <%= if @response do %>
                <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold border-green-500 bg-green-50 text-green-700">
                  Valid
                </span>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="p-4">
        <%= cond do %>
          <% @loading -> %>
            <div class="flex items-center justify-center py-8">
              <svg
                class="animate-spin h-6 w-6 text-primary"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                >
                </circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                >
                </path>
              </svg>
            </div>
          <% @error -> %>
            <div class="rounded border border-destructive bg-destructive/10 p-3 text-xs text-destructive">
              {@error}
            </div>
          <% @response -> %>
            <div class="space-y-3">
              <div class="flex border-b">
                <button
                  :for={tab <- ~w(body headers)}
                  phx-click="switch_response_tab"
                  phx-value-tab={tab}
                  class={[
                    "flex-1 px-3 py-2 text-xs font-medium border-b-2",
                    if(tab == @response_tab,
                      do: "border-primary text-primary",
                      else: "border-transparent text-muted-foreground hover:text-foreground"
                    )
                  ]}
                >
                  {response_tab_label(tab)}
                </button>
              </div>
              {render_response_content(assigns)}
            </div>
          <% true -> %>
            <p class="text-sm text-muted-foreground text-center py-8">
              Envie um request para ver a resposta
            </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_response_content(%{response_tab: "body"} = assigns) do
    ~H"""
    <pre class="overflow-x-auto rounded bg-muted p-3 text-xs font-mono max-h-80 overflow-y-auto"><code>{format_body(@response.body)}</code></pre>
    """
  end

  defp render_response_content(%{response_tab: "headers"} = assigns) do
    ~H"""
    <div class="space-y-1">
      <div
        :for={{key, value} <- @response.headers}
        class="flex gap-2 text-xs"
      >
        <span class="font-semibold text-muted-foreground min-w-[120px]">{key}</span>
        <span class="font-mono">{value}</span>
      </div>
    </div>
    """
  end

  defp format_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> body
    end
  end

  defp format_body(body), do: inspect(body)

  defp status_color(status) when status >= 200 and status < 300,
    do: "border-green-500 bg-green-50 text-green-700"

  defp status_color(status) when status >= 400 and status < 500,
    do: "border-yellow-500 bg-yellow-50 text-yellow-700"

  defp status_color(status) when status >= 500,
    do: "border-red-500 bg-red-50 text-red-700"

  defp status_color(_), do: "border bg-muted text-muted-foreground"

  defp response_tab_label("body"), do: "Body"
  defp response_tab_label("headers"), do: "Headers"
end
