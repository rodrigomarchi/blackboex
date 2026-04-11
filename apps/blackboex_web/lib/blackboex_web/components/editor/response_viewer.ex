defmodule BlackboexWeb.Components.Editor.ResponseViewer do
  @moduledoc """
  LiveComponent for displaying API test responses.
  Shows status badge, duration, formatted body, and headers.
  """

  use BlackboexWeb, :live_component

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.Shared.UnderlineTabs
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
            <span class="text-muted-caption">
              {@response.duration_ms}ms
            </span>
            <%= if @violations != [] do %>
              <.badge variant="warning">
                {length(@violations)} violation(s)
              </.badge>
            <% else %>
              <%= if @response do %>
                <.badge variant="success">
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
              <.underline_tabs
                tabs={[{"body", "Body"}, {"headers", "Headers"}]}
                active={@response_tab}
                click_event="switch_response_tab"
              />
              {render_response_content(assigns)}
            </div>
          <% true -> %>
            <p class="text-muted-description text-center py-8">
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
end
