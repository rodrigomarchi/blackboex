defmodule BlackboexWeb.Components.Editor.RequestBuilder do
  @moduledoc """
  LiveComponent for building and sending API test requests.
  Renders method selector, URL field, and sub-tabs for params/headers/body/auth.
  """

  use BlackboexWeb, :live_component

  import BlackboexWeb.Components.UI.FieldLabel
  import BlackboexWeb.Components.UI.InlineInput
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
            <svg
              class="animate-spin -ml-1 mr-2 h-4 w-4"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
              </circle>
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              >
              </path>
            </svg>
            Sending...
          <% else %>
            <.icon name="hero-paper-airplane-mini" class="size-3.5 text-emerald-300" /> Send
          <% end %>
        </.button>
      </div>

      <div class="rounded-lg border bg-card">
        <div class="flex border-b">
          <.button
            :for={tab <- ~w(params headers body auth)}
            variant="ghost"
            phx-click="switch_request_tab"
            phx-value-tab={tab}
            class={[
              "h-auto rounded-none flex-1 px-3 py-2 text-xs font-medium border-b-2 hover:bg-transparent",
              if(tab == @active_tab,
                do: "border-primary text-primary",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            {tab_label(tab)}
          </.button>
        </div>

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
          variant="ghost"
          phx-click="remove_param"
          phx-value-id={param.id}
          class="h-auto w-auto p-0 text-xs text-destructive hover:underline hover:bg-transparent"
        >
          ✕
        </.button>
      </div>
      <.button
        variant="ghost"
        phx-click="add_param"
        class="h-auto w-auto p-0 text-xs text-primary hover:underline hover:bg-transparent"
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
          variant="ghost"
          phx-click="remove_header"
          phx-value-id={header.id}
          class="h-auto w-auto p-0 text-xs text-destructive hover:underline hover:bg-transparent"
        >
          ✕
        </.button>
      </div>
      <.button
        variant="ghost"
        phx-click="add_header"
        class="h-auto w-auto p-0 text-xs text-primary hover:underline hover:bg-transparent"
      >
        + Add header
      </.button>
    </div>
    """
  end

  defp render_request_tab(%{active_tab: "body"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <div
        id="request-body-editor"
        phx-hook="CodeEditor"
        data-language="json"
        data-readonly="false"
        data-minimal="true"
        data-event="update_test_body"
        data-field="test_body_json"
        data-value={@body_json}
        class={[
          "rounded-md overflow-hidden border [&_.cm-editor]:min-h-[8rem]",
          if(@body_error, do: "border-destructive", else: "")
        ]}
        phx-update="ignore"
      >
      </div>
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
      <p class="text-xs text-muted-foreground">
        Sent as X-Api-Key header
      </p>
    </div>
    """
  end

  defp tab_label("params"), do: "Params"
  defp tab_label("headers"), do: "Headers"
  defp tab_label("body"), do: "Body"
  defp tab_label("auth"), do: "Auth"
end
