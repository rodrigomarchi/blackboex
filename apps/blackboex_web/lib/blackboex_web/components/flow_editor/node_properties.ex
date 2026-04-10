defmodule BlackboexWeb.Components.FlowEditor.NodeProperties do
  @moduledoc """
  Function components for rendering node-specific property forms
  in the flow editor's properties drawer.

  Each node type (start, elixir_code, condition, etc.) has its own
  `node_properties/1` clause that renders the appropriate form fields.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.FlowLive.Components.SchemaBuilder

  # ── Node-specific property forms ─────────────────────────────────────────

  attr :type, :string, required: true
  attr :data, :map, required: true
  attr :node_id, :string, required: true
  attr :tab, :string, default: "settings"
  attr :state_variables, :list, default: []
  attr :org_flows, :list, default: []
  attr :sub_flow_schema, :list, default: []

  def node_properties(%{type: "start"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.properties_tabs
        tabs={[
          {"Settings", "settings"},
          {"Payload Schema", "payload_schema"},
          {"State Schema", "state_schema"}
        ]}
        active={@tab}
      />

      <div :if={@tab == "settings"} class="space-y-4">
        <.prop_field
          label="Node Name"
          field="name"
          value={@data["name"] || "Start"}
          placeholder="Start"
          icon="hero-tag"
          icon_color="text-violet-400"
        />
        <.prop_field
          label="Description"
          field="description"
          value={@data["description"] || ""}
          placeholder="Describe what triggers this flow"
          type="textarea"
          icon="hero-chat-bubble-bottom-center-text"
          icon_color="text-sky-400"
        />
        <.prop_select
          label="Execution Mode"
          field="execution_mode"
          value={@data["execution_mode"] || "sync"}
          options={[{"Sync (request/response)", "sync"}, {"Async (polling)", "async"}]}
          icon="hero-bolt"
          icon_color="text-amber-400"
        />
        <.prop_field
          label="Timeout (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "30000"}
          placeholder="30000"
          type="number"
          icon="hero-clock"
          icon_color="text-orange-400"
        />
        <.prop_select
          label="Trigger Type"
          field="trigger_type"
          value={@data["trigger_type"] || "webhook"}
          options={[{"Webhook", "webhook"}, {"Manual", "manual"}, {"Schedule", "schedule"}]}
          icon="hero-signal"
          icon_color="text-green-400"
        />
      </div>

      <div :if={@tab == "payload_schema"}>
        <.schema_builder
          schema_id="payload_schema"
          fields={@data["payload_schema"] || []}
          label="Payload Fields"
        />
      </div>

      <div :if={@tab == "state_schema"}>
        <.schema_builder
          schema_id="state_schema"
          fields={@data["state_schema"] || []}
          show_initial_value={true}
          label="State Variables"
        />
      </div>
    </div>
    """
  end

  def node_properties(%{type: "elixir_code"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Elixir Code"}
        placeholder="Elixir Code"
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="What does this step do?"
        type="textarea"
        icon="hero-chat-bubble-bottom-center-text"
        icon_color="text-sky-400"
      />
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-code-bracket" class="size-3.5 text-purple-400" /> Code
        </label>
        <div
          id={"code-editor-#{@node_id}-code"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="code"
          data-value={@data["code"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 240px;"
        />
      </div>
      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "5000"}
        placeholder="5000"
        type="number"
        icon="hero-clock"
        icon_color="text-orange-400"
      />
      <div class="border-t pt-4 mt-4">
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-funnel" class="size-3.5 text-yellow-400" /> Skip Condition
        </label>
        <p class="text-xs text-muted-foreground mb-1.5">
          Skip this node when expression is true
        </p>
        <div
          id={"code-editor-#{@node_id}-skip_condition"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="skip_condition"
          data-value={@data["skip_condition"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 60px;"
        />
      </div>
      <div class="border-t pt-4 mt-4">
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-arrow-uturn-left" class="size-3.5 text-rose-400" /> Undo Code
        </label>
        <p class="text-xs text-muted-foreground mb-1.5">
          Rollback code if a downstream step fails. Has
          <code class="text-xs bg-muted px-1 rounded">result</code>
          binding.
        </p>
        <div
          id={"code-editor-#{@node_id}-undo_code"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="undo_code"
          data-value={@data["undo_code"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 100px;"
        />
      </div>
    </div>
    """
  end

  def node_properties(%{type: "condition"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Condition"}
        placeholder="Condition"
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="Describe the branching logic"
        type="textarea"
        icon="hero-chat-bubble-bottom-center-text"
        icon_color="text-sky-400"
      />
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-code-bracket" class="size-3.5 text-blue-400" /> Expression
        </label>
        <div
          id={"code-editor-#{@node_id}-expression"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="expression"
          data-value={@data["expression"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 120px;"
        />
      </div>
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-tag" class="size-3.5 text-teal-400" /> Branch Labels
        </label>
        <p class="text-xs text-muted-foreground mb-2">
          Name each output branch (one per line)
        </p>
        <textarea
          phx-blur="update_node_data"
          phx-value-field="branch_labels"
          rows="4"
          placeholder="Success\nError\nDefault"
          class="w-full rounded-lg border bg-background px-3 py-2 text-xs leading-relaxed focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        ><%= format_branch_labels(@data["branch_labels"]) %></textarea>
      </div>
    </div>
    """
  end

  def node_properties(%{type: "end"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.properties_tabs
        tabs={[{"Settings", "settings"}, {"Response Schema", "response_schema"}]}
        active={@tab}
      />

      <div :if={@tab == "settings"} class="space-y-4">
        <.prop_field
          label="Node Name"
          field="name"
          value={@data["name"] || "End"}
          placeholder="End"
          icon="hero-tag"
          icon_color="text-violet-400"
        />
        <.prop_field
          label="Description"
          field="description"
          value={@data["description"] || ""}
          placeholder="Describe how the flow ends"
          type="textarea"
          icon="hero-chat-bubble-bottom-center-text"
          icon_color="text-sky-400"
        />
        <.prop_select
          label="Output Mode"
          field="output_mode"
          value={@data["output_mode"] || "last_value"}
          options={[
            {"Last Value", "last_value"},
            {"Accumulate All", "accumulate"},
            {"Discard", "discard"}
          ]}
          icon="hero-arrow-down-tray"
          icon_color="text-emerald-400"
        />
      </div>

      <div :if={@tab == "response_schema"} class="space-y-4">
        <.schema_builder
          schema_id="response_schema"
          fields={@data["response_schema"] || []}
          label="Response Fields"
        />
        <.response_mapping
          mapping={@data["response_mapping"] || []}
          response_schema={@data["response_schema"] || []}
          state_variables={@state_variables}
        />
      </div>
    </div>
    """
  end

  def node_properties(%{type: "http_request"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.properties_tabs
        tabs={[{"Settings", "settings"}, {"Auth", "auth"}, {"Advanced", "advanced"}]}
        active={@tab}
      />

      <div :if={@tab == "settings"} class="space-y-4">
        <.prop_field
          label="Node Name"
          field="name"
          value={@data["name"] || "HTTP Request"}
          icon="hero-tag"
          icon_color="text-violet-400"
        />
        <.prop_select
          label="Method"
          field="method"
          value={@data["method"] || "GET"}
          options={[
            {"GET", "GET"},
            {"POST", "POST"},
            {"PUT", "PUT"},
            {"PATCH", "PATCH"},
            {"DELETE", "DELETE"}
          ]}
          icon="hero-command-line"
          icon_color="text-amber-400"
        />
        <.prop_field
          label="URL"
          field="url"
          value={@data["url"] || ""}
          placeholder="https://api.example.com/{{state.path}}"
          icon="hero-link"
          icon_color="text-blue-400"
        />
        <div>
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
            <.icon name="hero-document-text" class="size-3.5 text-emerald-400" /> Body Template
          </label>
          <div
            id={"code-editor-#{@node_id}-body_template"}
            phx-hook="CodeEditor"
            phx-update="ignore"
            data-language="json"
            data-event="update_node_data"
            data-field="body_template"
            data-value={@data["body_template"] || ""}
            class="w-full rounded-lg border overflow-hidden"
            style="height: 120px;"
          />
        </div>
      </div>

      <div :if={@tab == "auth"} class="space-y-4">
        <.prop_select
          label="Auth Type"
          field="auth_type"
          value={@data["auth_type"] || "none"}
          options={[
            {"None", "none"},
            {"Bearer Token", "bearer"},
            {"Basic Auth", "basic"},
            {"API Key", "api_key"}
          ]}
          icon="hero-lock-closed"
          icon_color="text-rose-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "bearer"}
          label="Token"
          field="auth_token"
          value={get_in(@data, ["auth_config", "token"]) || ""}
          placeholder="Bearer token"
          icon="hero-key"
          icon_color="text-amber-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "basic"}
          label="Username"
          field="auth_username"
          value={get_in(@data, ["auth_config", "username"]) || ""}
          icon="hero-user"
          icon_color="text-sky-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "basic"}
          label="Password"
          field="auth_password"
          value={get_in(@data, ["auth_config", "password"]) || ""}
          icon="hero-lock-closed"
          icon_color="text-rose-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "api_key"}
          label="Key Name"
          field="auth_key_name"
          value={get_in(@data, ["auth_config", "key_name"]) || ""}
          placeholder="X-API-Key"
          icon="hero-key"
          icon_color="text-amber-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "api_key"}
          label="Key Value"
          field="auth_key_value"
          value={get_in(@data, ["auth_config", "key_value"]) || ""}
          icon="hero-lock-closed"
          icon_color="text-rose-400"
        />
      </div>

      <div :if={@tab == "advanced"} class="space-y-4">
        <.prop_field
          label="Timeout (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "10000"}
          type="number"
          icon="hero-clock"
          icon_color="text-orange-400"
        />
        <.prop_field
          label="Max Retries"
          field="max_retries"
          value={@data["max_retries"] || "3"}
          type="number"
          icon="hero-arrow-path"
          icon_color="text-cyan-400"
        />
        <.prop_field
          label="Expected Status Codes"
          field="expected_status"
          value={format_status_codes(@data["expected_status"])}
          placeholder="200, 201"
          icon="hero-check-badge"
          icon_color="text-green-400"
        />
        <div class="border-t pt-4 mt-4">
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
            <.icon name="hero-funnel" class="size-3.5 text-yellow-400" /> Skip Condition
          </label>
          <p class="text-xs text-muted-foreground mb-1.5">
            Skip this node when expression is true
          </p>
          <div
            id={"code-editor-#{@node_id}-skip_condition"}
            phx-hook="CodeEditor"
            phx-update="ignore"
            data-language="elixir"
            data-event="update_node_data"
            data-field="skip_condition"
            data-value={@data["skip_condition"] || ""}
            class="w-full rounded-lg border overflow-hidden"
            style="height: 60px;"
          />
        </div>
        <div class="border-t pt-4 mt-4">
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
            <.icon name="hero-arrow-uturn-left" class="size-3.5 text-rose-400" /> Undo Request
          </label>
          <p class="text-xs text-muted-foreground mb-1.5">
            HTTP request to undo this action if a downstream step fails
          </p>
          <.prop_select
            label="Undo Method"
            field="undo_method"
            value={get_in(@data, ["undo_config", "method"]) || ""}
            options={[
              {"None", ""},
              {"DELETE", "DELETE"},
              {"POST", "POST"},
              {"PUT", "PUT"},
              {"PATCH", "PATCH"}
            ]}
            icon="hero-arrows-right-left"
            icon_color="text-rose-400"
          />
          <div class="mt-2">
            <.prop_field
              label="Undo URL"
              field="undo_url"
              value={get_in(@data, ["undo_config", "url"]) || ""}
              placeholder="https://api.example.com/resource/{{state.id}}"
              icon="hero-link"
              icon_color="text-rose-400"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  def node_properties(%{type: "delay"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Delay"}
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Duration (ms)"
        field="duration_ms"
        value={@data["duration_ms"] || "1000"}
        placeholder="1000"
        type="number"
        icon="hero-clock"
        icon_color="text-amber-400"
      />
      <.prop_field
        label="Max Duration (ms)"
        field="max_duration_ms"
        value={@data["max_duration_ms"] || "60000"}
        placeholder="60000"
        type="number"
        icon="hero-clock"
        icon_color="text-orange-400"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="Why is this delay needed?"
        type="textarea"
        icon="hero-chat-bubble-bottom-center-text"
        icon_color="text-sky-400"
      />
      <div class="border-t pt-4 mt-4">
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-funnel" class="size-3.5 text-yellow-400" /> Skip Condition
        </label>
        <p class="text-xs text-muted-foreground mb-1.5">
          Skip this node when expression is true
        </p>
        <div
          id={"code-editor-#{@node_id}-skip_condition"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="skip_condition"
          data-value={@data["skip_condition"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 60px;"
        />
      </div>
    </div>
    """
  end

  def node_properties(%{type: "sub_flow"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Sub-Flow"}
        icon="hero-tag"
        icon_color="text-violet-400"
      />

      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-squares-2x2" class="size-3.5 text-indigo-400" /> Sub-Flow
        </label>
        <select
          phx-change="select_sub_flow"
          name="flow_id"
          class="w-full rounded-lg border bg-background px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >
          <option value="">Select a flow...</option>
          <option
            :for={flow <- @org_flows}
            value={flow.id}
            selected={flow.id == @data["flow_id"]}
          >
            {flow.name}
          </option>
        </select>
      </div>

      <%= if @data["flow_id"] && @data["flow_id"] != "" do %>
        <div>
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-2">
            <.icon name="hero-arrows-right-left" class="size-3.5 text-teal-400" /> Input Mapping
          </label>
          <p class="text-xs text-muted-foreground mb-3">
            Map parent flow state/input to sub-flow payload fields
          </p>

          <%= if (@sub_flow_schema) == [] do %>
            <p class="text-xs text-muted-foreground italic">
              Selected flow has no payload schema defined.
              You can still add custom mappings below.
            </p>
          <% end %>

          <div class="space-y-3">
            <div
              :for={field <- @sub_flow_schema}
              class="space-y-1"
            >
              <div class="flex items-center gap-1.5">
                <span class="text-xs font-medium text-foreground">{field["name"]}</span>
                <span class="text-xs text-muted-foreground">({field["type"]})</span>
                <span class="text-xs text-muted-foreground">&larr;</span>
              </div>
              <div
                id={"code-editor-#{@node_id}-mapping-#{field["name"]}"}
                phx-hook="CodeEditor"
                phx-update="ignore"
                data-language="elixir"
                data-minimal="true"
                data-event="update_input_mapping"
                data-field={field["name"]}
                data-value={get_in(@data, ["input_mapping", field["name"]]) || ""}
                class="w-full rounded-lg border overflow-hidden"
                style="height: 36px;"
              />
            </div>
          </div>
        </div>
      <% end %>

      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "30000"}
        placeholder="30000"
        type="number"
        icon="hero-clock"
        icon_color="text-orange-400"
      />
      <div class="border-t pt-4 mt-4">
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-funnel" class="size-3.5 text-yellow-400" /> Skip Condition
        </label>
        <p class="text-xs text-muted-foreground mb-1.5">
          Skip this node when expression is true
        </p>
        <div
          id={"code-editor-#{@node_id}-skip_condition"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="skip_condition"
          data-value={@data["skip_condition"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 60px;"
        />
      </div>
    </div>
    """
  end

  def node_properties(%{type: "for_each"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.properties_tabs tabs={[{"Settings", "settings"}, {"Code", "code"}]} active={@tab} />

      <div :if={@tab == "settings"} class="space-y-4">
        <.prop_field
          label="Node Name"
          field="name"
          value={@data["name"] || "For Each"}
          icon="hero-tag"
          icon_color="text-violet-400"
        />
        <div>
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
            <.icon name="hero-funnel" class="size-3.5 text-teal-400" /> Source Expression
          </label>
          <div
            id={"code-editor-#{@node_id}-source_expression"}
            phx-hook="CodeEditor"
            phx-update="ignore"
            data-language="elixir"
            data-event="update_node_data"
            data-field="source_expression"
            data-value={@data["source_expression"] || ""}
            class="w-full rounded-lg border overflow-hidden"
            style="height: 60px;"
          />
        </div>
        <.prop_field
          label="Item Variable"
          field="item_variable"
          value={@data["item_variable"] || "item"}
          placeholder="item"
          icon="hero-variable"
          icon_color="text-purple-400"
        />
        <.prop_field
          label="Accumulator Key"
          field="accumulator"
          value={@data["accumulator"] || "results"}
          placeholder="results"
          icon="hero-archive-box"
          icon_color="text-amber-400"
        />
        <.prop_field
          label="Batch Size"
          field="batch_size"
          value={@data["batch_size"] || "10"}
          placeholder="10"
          type="number"
          icon="hero-squares-2x2"
          icon_color="text-indigo-400"
        />
        <.prop_field
          label="Timeout per Item (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "5000"}
          placeholder="5000"
          type="number"
          icon="hero-clock"
          icon_color="text-orange-400"
        />
        <div class="border-t pt-4 mt-4">
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
            <.icon name="hero-funnel" class="size-3.5 text-yellow-400" /> Skip Condition
          </label>
          <p class="text-xs text-muted-foreground mb-1.5">
            Skip this node when expression is true
          </p>
          <div
            id={"code-editor-#{@node_id}-skip_condition"}
            phx-hook="CodeEditor"
            phx-update="ignore"
            data-language="elixir"
            data-event="update_node_data"
            data-field="skip_condition"
            data-value={@data["skip_condition"] || ""}
            class="w-full rounded-lg border overflow-hidden"
            style="height: 60px;"
          />
        </div>
      </div>

      <div :if={@tab == "code"}>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-code-bracket" class="size-3.5 text-purple-400" /> Body Code
        </label>
        <div
          id={"code-editor-#{@node_id}-body_code"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="body_code"
          data-value={@data["body_code"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 200px;"
        />
      </div>
    </div>
    """
  end

  def node_properties(%{type: "webhook_wait"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Webhook Wait"}
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Event Type"
        field="event_type"
        value={@data["event_type"] || ""}
        placeholder="e.g. approval, payment.confirmed"
        icon="hero-bell-alert"
        icon_color="text-pink-400"
      />
      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "3600000"}
        placeholder="3600000"
        type="number"
        icon="hero-clock"
        icon_color="text-orange-400"
      />
      <.prop_field
        label="Resume Path"
        field="resume_path"
        value={@data["resume_path"] || ""}
        placeholder="e.g. data.approved"
        icon="hero-arrow-right-circle"
        icon_color="text-emerald-400"
      />
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-link" class="size-3.5 text-blue-400" /> Callback URL
        </label>
        <p class="rounded-lg border bg-muted/50 px-3 py-2 text-xs text-muted-foreground font-mono">
          POST /webhook/:token/resume/{@data["event_type"] || "<event_type>"}
        </p>
      </div>
      <div class="border-t pt-4 mt-4">
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-funnel" class="size-3.5 text-yellow-400" /> Skip Condition
        </label>
        <p class="text-xs text-muted-foreground mb-1.5">
          Skip this node when expression is true
        </p>
        <div
          id={"code-editor-#{@node_id}-skip_condition"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="skip_condition"
          data-value={@data["skip_condition"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 60px;"
        />
      </div>
    </div>
    """
  end

  def node_properties(%{type: "fail"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Fail"}
        placeholder="Fail"
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="When does this error occur?"
        type="textarea"
        icon="hero-chat-bubble-bottom-center-text"
        icon_color="text-sky-400"
      />
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-exclamation-triangle" class="size-3.5 text-red-400" /> Error Message
        </label>
        <p class="text-xs text-muted-foreground mb-1.5">
          Elixir expression with <code class="text-xs bg-muted px-1 rounded">input</code>
          and <code class="text-xs bg-muted px-1 rounded">state</code>
          bindings
        </p>
        <div
          id={"code-editor-#{@node_id}-message"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="message"
          data-value={@data["message"] || ~S|"Error: #{input["reason"]}"|}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 100px;"
        />
      </div>
      <.prop_select
        label="Include State"
        field="include_state"
        value={to_string(@data["include_state"] || false)}
        options={[{"No", "false"}, {"Yes", "true"}]}
        icon="hero-document-text"
        icon_color="text-amber-400"
      />
    </div>
    """
  end

  def node_properties(%{type: "debug"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Debug"}
        placeholder="Debug"
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-bug-ant" class="size-3.5 text-purple-400" /> Expression
        </label>
        <p class="text-xs text-muted-foreground mb-1.5">
          Elixir expression to inspect. Leave empty to log the input.
        </p>
        <div
          id={"code-editor-#{@node_id}-expression"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="expression"
          data-value={@data["expression"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 100px;"
        />
      </div>
      <.prop_select
        label="Log Level"
        field="log_level"
        value={@data["log_level"] || "info"}
        options={[{"Debug", "debug"}, {"Info", "info"}, {"Warning", "warning"}]}
        icon="hero-signal"
        icon_color="text-cyan-400"
      />
      <.prop_field
        label="State Key"
        field="state_key"
        value={@data["state_key"] || "debug"}
        placeholder="debug"
        icon="hero-key"
        icon_color="text-emerald-400"
      />
    </div>
    """
  end

  def node_properties(assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || ""}
        placeholder="Node name"
      />
    </div>
    """
  end

  # ── Reusable property field components ───────────────────────────────────

  @doc false
  def format_branch_labels(labels) when is_map(labels) do
    labels
    |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
    |> Enum.map_join("\n", fn {_k, v} -> v end)
  end

  def format_branch_labels(labels) when is_binary(labels), do: labels
  def format_branch_labels(_), do: ""

  @doc false
  def format_status_codes(codes) when is_list(codes), do: Enum.join(codes, ", ")
  def format_status_codes(_), do: "200, 201"

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :type, :string, default: "text"
  attr :icon, :string, default: nil
  attr :icon_color, :string, default: "text-blue-400"

  def prop_field(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
        <.icon :if={@icon} name={@icon} class={"size-3.5 #{@icon_color}"} />
        {@label}
      </label>
      <textarea
        phx-blur="update_node_data"
        phx-value-field={@field}
        rows="3"
        placeholder={@placeholder}
        class="w-full rounded-lg border bg-background px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      >{@value}</textarea>
    </div>
    """
  end

  def prop_field(assigns) do
    ~H"""
    <div>
      <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
        <.icon :if={@icon} name={@icon} class={"size-3.5 #{@icon_color}"} />
        {@label}
      </label>
      <input
        type={@type}
        phx-blur="update_node_data"
        phx-value-field={@field}
        value={@value}
        placeholder={@placeholder}
        class="w-full rounded-lg border bg-background px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: ""
  attr :options, :list, required: true
  attr :icon, :string, default: nil
  attr :icon_color, :string, default: "text-blue-400"

  def prop_select(assigns) do
    ~H"""
    <div>
      <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
        <.icon :if={@icon} name={@icon} class={"size-3.5 #{@icon_color}"} />
        {@label}
      </label>
      <select
        phx-change="update_node_data"
        phx-value-field={@field}
        class="w-full rounded-lg border bg-background px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      >
        <option :for={{label, val} <- @options} value={val} selected={val == @value}>
          {label}
        </option>
      </select>
    </div>
    """
  end

  # ── Properties tab bar ───────────────────────────────────────────────────

  attr :tabs, :list, required: true
  attr :active, :string, required: true

  def properties_tabs(assigns) do
    ~H"""
    <div class="flex border-b -mx-4 px-4">
      <button
        :for={{label, id} <- @tabs}
        type="button"
        phx-click="set_properties_tab"
        phx-value-tab={id}
        class={[
          "px-3 py-2 text-xs font-medium border-b-2 -mb-px transition-colors",
          if(id == @active,
            do: "border-primary text-foreground",
            else:
              "border-transparent text-muted-foreground hover:text-foreground hover:border-muted-foreground/50"
          )
        ]}
      >
        {label}
      </button>
    </div>
    """
  end
end
