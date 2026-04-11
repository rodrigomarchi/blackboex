defmodule BlackboexWeb.Components.Editor.RequestBuilder do
  @moduledoc """
  LiveComponent for building and sending API test requests.
  Renders method selector, URL field, and sub-tabs for params/headers/body/auth.
  """

  use BlackboexWeb, :live_component

  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.Shared.UnderlineTabs
  import BlackboexWeb.Components.UI.FieldLabel
  import BlackboexWeb.Components.UI.InlineInput
  import BlackboexWeb.Components.Spinner
  import BlackboexWeb.Components.UI.InlineSelect

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3" id="request-builder">
      <div class="flex items-center gap-2">
        <.inline_select
          name="method"
          value={@method}
          options={Enum.map(~w(GET POST PUT PATCH DELETE), &{&1, &1})}
          phx-change="update_test_method"
          class="rounded-md px-2 py-1.5 font-semibold w-28"
        />

        <.inline_input
          name="url"
          value={@url}
          phx-change="update_test_url"
          class="flex-1 rounded-md px-3 py-1.5 font-mono"
          readonly
        />

        <.button
          variant="primary"
          phx-click="send_request"
          disabled={@loading}
          class="h-auto inline-flex items-center rounded-md px-4 py-1.5"
        >
          <%= if @loading do %>
            <.spinner class="-ml-1 mr-2 size-4" /> Sending...
          <% else %>
            <.icon name="hero-paper-airplane-mini" class="size-3.5 text-accent-emerald" /> Send
          <% end %>
        </.button>
      </div>

      <div class="rounded-lg border bg-card">
        <.underline_tabs
          tabs={[{"params", "Params"}, {"headers", "Headers"}, {"body", "Body"}, {"auth", "Auth"}]}
          active={@active_tab}
          click_event="switch_request_tab"
        />

        <div class="p-3">
          {render_request_tab(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp render_request_tab(%{active_tab: "params"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <div :for={param <- @params} class="flex items-center gap-2">
        <.inline_input
          value={param.key}
          placeholder="Key"
          phx-change="update_param_key"
          phx-value-id={param.id}
          name="param_key"
          class="flex-1 rounded-md px-2 py-1 text-xs"
        />
        <.inline_input
          value={param.value}
          placeholder="Value"
          phx-change="update_param_value"
          phx-value-id={param.id}
          name="param_value"
          class="flex-1 rounded-md px-2 py-1 text-xs"
        />
        <.button
          variant="link"
          size="icon-xs"
          phx-click="remove_param"
          phx-value-id={param.id}
          class="text-xs text-destructive"
        >
          ✕
        </.button>
      </div>
      <.button
        variant="link"
        size="icon-xs"
        phx-click="add_param"
        class="text-xs"
      >
        + Add param
      </.button>
    </div>
    """
  end

  defp render_request_tab(%{active_tab: "headers"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <div :for={header <- @headers} class="flex items-center gap-2">
        <.inline_input
          value={header.key}
          placeholder="Key"
          phx-change="update_header_key"
          phx-value-id={header.id}
          name="header_key"
          class="flex-1 rounded-md px-2 py-1 text-xs"
        />
        <.inline_input
          value={header.value}
          placeholder="Value"
          phx-change="update_header_value"
          phx-value-id={header.id}
          name="header_value"
          class="flex-1 rounded-md px-2 py-1 text-xs"
        />
        <.button
          variant="link"
          size="icon-xs"
          phx-click="remove_header"
          phx-value-id={header.id}
          class="text-xs text-destructive"
        >
          ✕
        </.button>
      </div>
      <.button
        variant="link"
        size="icon-xs"
        phx-click="add_header"
        class="text-xs"
      >
        + Add header
      </.button>
    </div>
    """
  end

  defp render_request_tab(%{active_tab: "body"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.code_editor_field
        id="request-body-editor"
        value={@body_json}
        readonly={false}
        event="update_test_body"
        field="test_body_json"
        class={["[&_.cm-editor]:min-h-[8rem]", if(@body_error, do: "border-destructive", else: "")]}
      />
      <%= if @body_error do %>
        <p class="text-xs text-destructive">{@body_error}</p>
      <% end %>
    </div>
    """
  end

  defp render_request_tab(%{active_tab: "auth"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.field_label class="mb-0">API Key</.field_label>
      <.inline_input
        name="test_api_key"
        value={@api_key}
        phx-change="update_test_api_key"
        placeholder="Enter API key"
        class="rounded-md px-2 py-1 text-xs font-mono"
      />
      <p class="text-muted-caption">
        Sent as X-Api-Key header
      </p>
    </div>
    """
  end
end
