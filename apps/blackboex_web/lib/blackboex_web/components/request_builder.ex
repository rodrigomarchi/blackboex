defmodule BlackboexWeb.Components.RequestBuilder do
  @moduledoc """
  LiveComponent for building and sending API test requests.
  Renders method selector, URL field, and sub-tabs for params/headers/body/auth.
  """

  use BlackboexWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3" id="request-builder">
      <div class="flex items-center gap-2">
        <select
          name="method"
          phx-change="update_test_method"
          class="rounded-md border bg-background px-2 py-1.5 text-sm font-semibold w-28"
        >
          <option :for={m <- ~w(GET POST PUT PATCH DELETE)} value={m} selected={m == @method}>
            {m}
          </option>
        </select>

        <input
          type="text"
          name="url"
          value={@url}
          phx-change="update_test_url"
          class="flex-1 rounded-md border bg-background px-3 py-1.5 text-sm font-mono"
          readonly
        />

        <button
          phx-click="send_request"
          disabled={@loading}
          class="inline-flex items-center rounded-md bg-primary px-4 py-1.5 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
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
            Send
          <% end %>
        </button>
      </div>

      <div class="rounded-lg border bg-card">
        <div class="flex border-b">
          <button
            :for={tab <- ~w(params headers body auth)}
            phx-click="switch_request_tab"
            phx-value-tab={tab}
            class={[
              "flex-1 px-3 py-2 text-xs font-medium border-b-2",
              if(tab == @active_tab,
                do: "border-primary text-primary",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            {tab_label(tab)}
          </button>
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
        <input
          type="text"
          value={param.key}
          placeholder="Key"
          phx-change="update_param_key"
          phx-value-id={param.id}
          name="param_key"
          class="flex-1 rounded-md border bg-background px-2 py-1 text-xs"
        />
        <input
          type="text"
          value={param.value}
          placeholder="Value"
          phx-change="update_param_value"
          phx-value-id={param.id}
          name="param_value"
          class="flex-1 rounded-md border bg-background px-2 py-1 text-xs"
        />
        <button
          phx-click="remove_param"
          phx-value-id={param.id}
          class="text-xs text-destructive hover:underline"
        >
          ✕
        </button>
      </div>
      <button phx-click="add_param" class="text-xs text-primary hover:underline">
        + Add param
      </button>
    </div>
    """
  end

  defp render_request_tab(%{active_tab: "headers"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <div :for={header <- @headers} class="flex items-center gap-2">
        <input
          type="text"
          value={header.key}
          placeholder="Key"
          phx-change="update_header_key"
          phx-value-id={header.id}
          name="header_key"
          class="flex-1 rounded-md border bg-background px-2 py-1 text-xs"
        />
        <input
          type="text"
          value={header.value}
          placeholder="Value"
          phx-change="update_header_value"
          phx-value-id={header.id}
          name="header_value"
          class="flex-1 rounded-md border bg-background px-2 py-1 text-xs"
        />
        <button
          phx-click="remove_header"
          phx-value-id={header.id}
          class="text-xs text-destructive hover:underline"
        >
          ✕
        </button>
      </div>
      <button phx-click="add_header" class="text-xs text-primary hover:underline">
        + Add header
      </button>
    </div>
    """
  end

  defp render_request_tab(%{active_tab: "body"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <textarea
        name="test_body_json"
        rows="6"
        phx-change="update_test_body"
        class={[
          "w-full rounded-md border bg-background px-2 py-1 text-xs font-mono",
          if(@body_error, do: "border-destructive", else: "")
        ]}
        placeholder="{}"
      >{@body_json}</textarea>
      <%= if @body_error do %>
        <p class="text-xs text-destructive">{@body_error}</p>
      <% end %>
    </div>
    """
  end

  defp render_request_tab(%{active_tab: "auth"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <label class="text-xs text-muted-foreground">API Key</label>
      <input
        type="text"
        name="test_api_key"
        value={@api_key}
        phx-change="update_test_api_key"
        placeholder="Enter API key"
        class="w-full rounded-md border bg-background px-2 py-1 text-xs font-mono"
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
