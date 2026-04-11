defmodule BlackboexWeb.ApiLive.Edit.PublishLiveComponents do
  @moduledoc """
  Function components for the PublishLive view.
  Each component renders a distinct visual section of the publish tab.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.InlineCode
  import BlackboexWeb.Components.UI.FieldLabel
  import BlackboexWeb.Components.UI.SectionHeading
  import BlackboexWeb.Components.Shared.StatMini

  import BlackboexWeb.ApiLive.Edit.Helpers, only: [time_ago: 1]

  import BlackboexWeb.ApiLive.Edit.PublishLiveHelpers,
    only: [
      published_version?: 2,
      can_publish_version?: 3,
      compilation_status_classes: 1,
      compilation_status_label: 1,
      humanize_source: 1
    ]

  # ── Status Header ─────────────────────────────────────────────────────

  attr :api, :map, required: true
  attr :org, :map, required: true
  attr :published_version, :map, default: nil

  @spec status_header(map()) :: Phoenix.LiveView.Rendered.t()
  def status_header(assigns) do
    ~H"""
    <div class="rounded-lg border p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <span class="text-muted-caption">Status</span>
          <.badge variant="status" class={api_status_border(@api.status)}>
            {@api.status}
          </.badge>
        </div>
        <.button
          :if={@api.status == "compiled"}
          variant="info"
          size="compact"
          phx-click="publish"
          class="font-medium"
        >
          <.icon name="hero-rocket-launch" class="mr-1.5 size-3.5" /> Publish API
        </.button>
        <.button
          :if={@api.status == "published"}
          variant="outline-destructive"
          size="compact"
          phx-click="request_confirm"
          phx-value-action="unpublish"
          class="font-medium"
        >
          <.icon name="hero-arrow-down-circle" class="mr-1.5 size-3.5" /> Unpublish
        </.button>
      </div>

      <div class="flex items-center gap-2 text-xs">
        <span class="text-muted-foreground">URL</span>
        <.inline_code>/api/{@org.slug}/{@api.slug}</.inline_code>
        <.button
          variant="link"
          size="icon-xs"
          phx-click="copy_url"
          class="text-2xs"
        >
          <.icon name="hero-clipboard-document-mini" class="mr-1 size-3 text-accent-sky" />Copy
        </.button>
        <%= if @api.status == "draft" do %>
          <span class="text-muted-foreground">(preview)</span>
        <% end %>
      </div>

      <%= if @api.status == "published" && @published_version do %>
        <div class="flex items-center gap-2 text-xs">
          <.badge variant="success" class="gap-1 font-semibold">
            <.icon name="hero-signal" class="size-3 text-accent-emerald" /> LIVE
          </.badge>
          <span>v{@published_version.version_number}</span>
          <span :if={@published_version.version_label} class="text-muted-foreground">
            ({@published_version.version_label})
          </span>
          <span class="text-muted-foreground">
            published {time_ago(@published_version.inserted_at)}
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Version Timeline ──────────────────────────────────────────────────

  attr :versions, :list, required: true
  attr :published_version, :map, default: nil
  attr :api_status, :string, required: true

  @spec version_timeline(map()) :: Phoenix.LiveView.Rendered.t()
  def version_timeline(assigns) do
    ~H"""
    <div>
      <.section_heading level="h3" variant="label">Versions</.section_heading>
      <%= if @versions == [] do %>
        <p class="text-muted-description">
          No versions yet. Save to create the first version.
        </p>
      <% else %>
        <div class="space-y-2">
          <%= for version <- @versions do %>
            <div class={[
              "rounded border p-3 text-xs space-y-1",
              if(published_version?(version, @published_version),
                do: "border-success bg-success/5",
                else: ""
              )
            ]}>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="font-semibold">v{version.version_number}</span>
                  <%= if published_version?(version, @published_version) do %>
                    <.badge
                      size="xs"
                      variant="status"
                      class="gap-1 bg-success/10 text-success-foreground font-semibold"
                    >
                      LIVE
                    </.badge>
                  <% end %>
                  <.badge
                    size="xs"
                    variant="status"
                    class={compilation_status_classes(version.compilation_status)}
                  >
                    {compilation_status_label(version.compilation_status)}
                  </.badge>
                </div>
                <span class="text-muted-foreground">
                  {Calendar.strftime(version.inserted_at, "%H:%M")}
                </span>
              </div>

              <div class="text-muted-foreground">
                {humanize_source(version.source)}
                <%= if version.diff_summary do %>
                  — {version.diff_summary}
                <% end %>
              </div>

              <div class="flex gap-2">
                <.button
                  variant="link"
                  size="icon-xs"
                  phx-click="view_version"
                  phx-value-number={version.version_number}
                >
                  <.icon name="hero-eye-mini" class="mr-1 size-3" />View
                </.button>
                <.button
                  :if={can_publish_version?(version, @published_version, @api_status)}
                  variant="link"
                  size="icon-xs"
                  phx-click="request_confirm"
                  phx-value-action="publish_version"
                  phx-value-number={version.version_number}
                  class="text-info font-medium"
                >
                  <.icon name="hero-rocket-launch-mini" class="mr-1 size-3" />Publish this version
                </.button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Metrics Grid ──────────────────────────────────────────────────────

  attr :metrics, :map, required: true

  @spec metrics_grid(map()) :: Phoenix.LiveView.Rendered.t()
  def metrics_grid(assigns) do
    ~H"""
    <div>
      <.section_heading level="h3" variant="label">Metrics (24h)</.section_heading>
      <div class="grid grid-cols-4 gap-3">
        <.stat_mini
          value={@metrics.count_24h}
          label="Total Calls"
          icon="hero-signal-mini"
          icon_class="text-accent-sky"
        />
        <.stat_mini value={@metrics.success_rate} label="Success Rate" />
        <.stat_mini
          value={"#{@metrics.avg_latency}ms"}
          label="Avg Latency"
          icon="hero-clock-mini"
          icon_class="text-accent-amber"
        />
        <.stat_mini
          value={@metrics[:error_count] || 0}
          label="Errors"
          icon="hero-exclamation-circle-mini"
          icon_class="text-accent-red"
        />
      </div>
    </div>
    """
  end

  # ── Authentication Section ────────────────────────────────────────────

  attr :api, :map, required: true
  attr :keys_summary, :map, required: true

  @spec auth_section(map()) :: Phoenix.LiveView.Rendered.t()
  def auth_section(assigns) do
    ~H"""
    <div>
      <.section_heading level="h3" variant="label">Authentication</.section_heading>
      <div class="rounded-lg border p-4 space-y-3">
        <.form for={%{}} as={:publish_settings} phx-submit="save_publish_settings">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <.input
                type="checkbox"
                id="requires_auth"
                name="requires_auth"
                value={@api.requires_auth}
                class="rounded border"
              />
              <.field_label for="requires_auth" class="mb-0">
                Require API key
              </.field_label>
            </div>
            <.button
              type="submit"
              variant="primary"
              size="compact"
              class="font-medium"
            >
              <.icon name="hero-check" class="mr-1.5 size-3.5" /> Save
            </.button>
          </div>
        </.form>

        <div class="border-t pt-3 space-y-2">
          <div class="flex items-center justify-between text-xs">
            <span class="text-muted-foreground">
              {@keys_summary.active_count} active
              <%= if @keys_summary.revoked_count > 0 do %>
                , {@keys_summary.revoked_count} revoked
              <% end %>
            </span>
            <.link
              href="/api-keys"
              class="link-primary font-medium"
            >
              <.icon name="hero-key-mini" class="mr-1 size-3 text-accent-amber" />Manage Keys
            </.link>
          </div>
          <%= if @keys_summary.active_keys != [] do %>
            <div class="flex flex-wrap gap-1">
              <.inline_code :for={key <- @keys_summary.active_keys} class="px-2 text-2xs">
                {key.key_prefix}...
              </.inline_code>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Documentation Section ─────────────────────────────────────────────

  attr :org, :map, required: true
  attr :api, :map, required: true

  @spec docs_section(map()) :: Phoenix.LiveView.Rendered.t()
  def docs_section(assigns) do
    ~H"""
    <div>
      <.section_heading level="h3" variant="label">Documentation</.section_heading>
      <div class="space-y-2">
        <div class="flex items-center justify-between rounded border p-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-document-text" class="size-4 text-accent-blue" />
            <span class="text-sm">Swagger UI</span>
          </div>
          <.link
            href={"/api/#{@org.slug}/#{@api.slug}/docs"}
            target="_blank"
            class="link-primary"
          >
            Open
          </.link>
        </div>
        <div class="flex items-center justify-between rounded border p-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-code-bracket" class="size-4 text-accent-purple" />
            <span class="text-sm">OpenAPI JSON</span>
          </div>
          <.link
            href={"/api/#{@org.slug}/#{@api.slug}/openapi.json"}
            target="_blank"
            class="link-primary"
          >
            Open
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
