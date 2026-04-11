defmodule BlackboexWeb.Components.Editor.ResponseViewer do
  @moduledoc """
  LiveComponent for displaying API test responses.
  Shows status badge, duration, formatted body, and headers.
  """

  use BlackboexWeb, :live_component

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.Spinner
  import BlackboexWeb.Components.UI.AlertBanner
  import BlackboexWeb.Components.UI.SectionHeading

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-lg border bg-card text-card-foreground shadow-sm" id="response-viewer">
      <div class="flex items-center justify-between border-b px-4 py-2">
        <.section_heading
          level="h3"
          icon="hero-arrow-down-on-square-mini"
          icon_class="size-3.5 text-accent-blue"
          class="!text-sm !font-semibold !text-foreground"
        >
          Response
        </.section_heading>
        <%= if @response do %>
          <div class="flex items-center gap-2">
            <.badge variant="status" class={status_color(@response.status)}>
              {@response.status}
            </.badge>
            <span class="text-xs text-muted-foreground">
              {@response.duration_ms}ms
            </span>
            <%= if @violations != [] do %>
              <.badge variant="status" class="border-warning bg-warning/10 text-warning-foreground">
                {length(@violations)} violation(s)
              </.badge>
            <% else %>
              <%= if @response do %>
                <.badge variant="status" class="border-success bg-success/10 text-success-foreground">
                  Valid
                </.badge>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="p-4">
        <%= cond do %>
          <% @loading -> %>
            <div class="flex items-center justify-center py-8">
              <.spinner class="size-6 text-primary" />
            </div>
          <% @error -> %>
            <.alert_banner variant="destructive" icon="hero-exclamation-circle">
              {@error}
            </.alert_banner>
          <% @response -> %>
            <div class="space-y-3">
              <div class="flex border-b">
                <.button
                  :for={tab <- ~w(body headers)}
                  variant="ghost"
                  phx-click="switch_response_tab"
                  phx-value-tab={tab}
                  class={[
                    "h-auto rounded-none flex-1 px-3 py-2 text-xs font-medium border-b-2 hover:bg-transparent",
                    if(tab == @response_tab,
                      do: "border-primary text-primary",
                      else: "border-transparent text-muted-foreground hover:text-foreground"
                    )
                  ]}
                >
                  {response_tab_label(tab)}
                </.button>
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
    <.code_editor_field
      id="response-body-viewer"
      value={format_body(@response.body)}
      max_height="max-h-80"
      class="rounded"
    />
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
    do: "border-success bg-success/10 text-success-foreground"

  defp status_color(status) when status >= 400 and status < 500,
    do: "border-warning bg-warning/10 text-warning-foreground"

  defp status_color(status) when status >= 500,
    do: "border-destructive bg-destructive/10 text-destructive"

  defp status_color(_), do: "border bg-muted text-muted-foreground"

  defp response_tab_label("body"), do: "Body"
  defp response_tab_label("headers"), do: "Headers"
end
