defmodule BlackboexWeb.Components.FlowEditor.NodeProperties do
  @moduledoc """
  Function components for rendering node-specific property forms
  in the flow editor's properties drawer.

  Each node type (start, elixir_code, condition, etc.) has its own
  `node_properties/1` clause that renders the appropriate form fields.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Shared.InlineCode
  import BlackboexWeb.Components.Shared.UnderlineTabs
  import BlackboexWeb.Components.UI.FieldLabel
  import BlackboexWeb.Components.UI.InlineInput
  import BlackboexWeb.Components.UI.InlineSelect
  import BlackboexWeb.Components.UI.InlineTextarea
  import BlackboexWeb.FlowLive.Components.SchemaBuilder
  import BlackboexWeb.Components.Shared.CodeEditorField

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
          icon_color="text-accent-violet"
        />
        <.prop_field
          label="Description"
          field="description"
          value={@data["description"] || ""}
          placeholder="Describe what triggers this flow"
          type="textarea"
          icon="hero-chat-bubble-bottom-center-text"
          icon_color="text-accent-sky"
        />
        <.prop_select
          label="Execution Mode"
          field="execution_mode"
          value={@data["execution_mode"] || "sync"}
          options={[{"Sync (request/response)", "sync"}, {"Async (polling)", "async"}]}
          icon="hero-bolt"
          icon_color="text-accent-amber"
        />
        <.prop_field
          label="Timeout (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "30000"}
          placeholder="30000"
          type="number"
          icon="hero-clock"
          icon_color="text-accent-orange"
        />
        <.prop_select
          label="Trigger Type"
          field="trigger_type"
          value={@data["trigger_type"] || "webhook"}
          options={[{"Webhook", "webhook"}, {"Manual", "manual"}, {"Schedule", "schedule"}]}
          icon="hero-signal"
          icon_color="text-accent-emerald"
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
      <.node_common_fields
        data={@data}
        name_default="Elixir Code"
        name_placeholder="Elixir Code"
        description_placeholder="What does this step do?"
      />
      <div>
        <.field_label icon="hero-code-bracket" icon_color="text-accent-purple">Code</.field_label>
        <.code_editor_field
          id={"code-editor-#{@node_id}-code"}
          value={@data["code"] || ""}
          language="elixir"
          readonly={false}
          event="update_node_data"
          field="code"
          class="w-full rounded-lg"
          height="240px"
          max_height=""
        />
      </div>
      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "5000"}
        placeholder="5000"
        type="number"
        icon="hero-clock"
        icon_color="text-accent-orange"
      />
      <.skip_condition_fields node_id={@node_id} skip_condition={@data["skip_condition"] || ""} />
      <div class="border-t pt-4 mt-4">
        <.field_label icon="hero-arrow-uturn-left" icon_color="text-accent-rose">
          Undo Code
        </.field_label>
        <p class="text-muted-caption mb-1.5">
          Rollback code if a downstream step fails. Has
          <.inline_code>result</.inline_code>
          binding.
        </p>
        <.code_editor_field
          id={"code-editor-#{@node_id}-undo_code"}
          value={@data["undo_code"] || ""}
          language="elixir"
          readonly={false}
          event="update_node_data"
          field="undo_code"
          class="w-full rounded-lg"
          height="100px"
          max_height=""
        />
      </div>
    </div>
    """
  end

  def node_properties(%{type: "condition"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.node_common_fields
        data={@data}
        name_default="Condition"
        name_placeholder="Condition"
        description_placeholder="Describe the branching logic"
      />
      <div>
        <.field_label icon="hero-code-bracket" icon_color="text-accent-blue">Expression</.field_label>
        <.code_editor_field
          id={"code-editor-#{@node_id}-expression"}
          value={@data["expression"] || ""}
          language="elixir"
          readonly={false}
          event="update_node_data"
          field="expression"
          class="w-full rounded-lg"
          height="120px"
          max_height=""
        />
      </div>
      <div>
        <.field_label icon="hero-tag" icon_color="text-accent-teal">Branch Labels</.field_label>
        <p class="text-muted-caption mb-2">
          Name each output branch (one per line)
        </p>
        <.inline_textarea
          value={format_branch_labels(@data["branch_labels"])}
          rows="4"
          placeholder="Success\nError\nDefault"
          class="text-xs leading-relaxed"
          phx-blur="update_node_data"
          phx-value-field="branch_labels"
        />
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
        <.node_common_fields
          data={@data}
          name_default="End"
          name_placeholder="End"
          description_placeholder="Describe how the flow ends"
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
          icon_color="text-accent-emerald"
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
          icon_color="text-accent-violet"
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
          icon_color="text-accent-amber"
        />
        <.prop_field
          label="URL"
          field="url"
          value={@data["url"] || ""}
          placeholder="https://api.example.com/{{state.path}}"
          icon="hero-link"
          icon_color="text-accent-blue"
        />
        <div>
          <.field_label icon="hero-document-text" icon_color="text-accent-emerald">
            Body Template
          </.field_label>
          <.code_editor_field
            id={"code-editor-#{@node_id}-body_template"}
            value={@data["body_template"] || ""}
            language="json"
            readonly={false}
            event="update_node_data"
            field="body_template"
            class="w-full rounded-lg"
            height="120px"
            max_height=""
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
          icon_color="text-accent-rose"
        />
        <.prop_field
          :if={@data["auth_type"] == "bearer"}
          label="Token"
          field="auth_token"
          value={get_in(@data, ["auth_config", "token"]) || ""}
          placeholder="Bearer token"
          icon="hero-key"
          icon_color="text-accent-amber"
        />
        <.prop_field
          :if={@data["auth_type"] == "basic"}
          label="Username"
          field="auth_username"
          value={get_in(@data, ["auth_config", "username"]) || ""}
          icon="hero-user"
          icon_color="text-accent-sky"
        />
        <.prop_field
          :if={@data["auth_type"] == "basic"}
          label="Password"
          field="auth_password"
          value={get_in(@data, ["auth_config", "password"]) || ""}
          icon="hero-lock-closed"
          icon_color="text-accent-rose"
        />
        <.prop_field
          :if={@data["auth_type"] == "api_key"}
          label="Key Name"
          field="auth_key_name"
          value={get_in(@data, ["auth_config", "key_name"]) || ""}
          placeholder="X-API-Key"
          icon="hero-key"
          icon_color="text-accent-amber"
        />
        <.prop_field
          :if={@data["auth_type"] == "api_key"}
          label="Key Value"
          field="auth_key_value"
          value={get_in(@data, ["auth_config", "key_value"]) || ""}
          icon="hero-lock-closed"
          icon_color="text-accent-rose"
        />
      </div>

      <div :if={@tab == "advanced"} class="space-y-4">
        <.prop_field
          label="Timeout (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "10000"}
          type="number"
          icon="hero-clock"
          icon_color="text-accent-orange"
        />
        <.prop_field
          label="Max Retries"
          field="max_retries"
          value={@data["max_retries"] || "3"}
          type="number"
          icon="hero-arrow-path"
          icon_color="text-accent-cyan"
        />
        <.prop_field
          label="Expected Status Codes"
          field="expected_status"
          value={format_status_codes(@data["expected_status"])}
          placeholder="200, 201"
          icon="hero-check-badge"
          icon_color="text-accent-emerald"
        />
        <.skip_condition_fields node_id={@node_id} skip_condition={@data["skip_condition"] || ""} />
        <div class="border-t pt-4 mt-4">
          <.field_label icon="hero-arrow-uturn-left" icon_color="text-accent-rose">
            Undo Request
          </.field_label>
          <p class="text-muted-caption mb-1.5">
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
            icon_color="text-accent-rose"
          />
          <div class="mt-2">
            <.prop_field
              label="Undo URL"
              field="undo_url"
              value={get_in(@data, ["undo_config", "url"]) || ""}
              placeholder="https://api.example.com/resource/{{state.id}}"
              icon="hero-link"
              icon_color="text-accent-rose"
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
        icon_color="text-accent-violet"
      />
      <.prop_field
        label="Duration (ms)"
        field="duration_ms"
        value={@data["duration_ms"] || "1000"}
        placeholder="1000"
        type="number"
        icon="hero-clock"
        icon_color="text-accent-amber"
      />
      <.prop_field
        label="Max Duration (ms)"
        field="max_duration_ms"
        value={@data["max_duration_ms"] || "60000"}
        placeholder="60000"
        type="number"
        icon="hero-clock"
        icon_color="text-accent-orange"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="Why is this delay needed?"
        type="textarea"
        icon="hero-chat-bubble-bottom-center-text"
        icon_color="text-accent-sky"
      />
      <.skip_condition_fields node_id={@node_id} skip_condition={@data["skip_condition"] || ""} />
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
        icon_color="text-accent-violet"
      />

      <div>
        <.field_label icon="hero-squares-2x2" icon_color="text-accent-purple">Sub-Flow</.field_label>
        <.inline_select
          name="flow_id"
          value={@data["flow_id"]}
          options={[{"Select a flow...", ""} | Enum.map(@org_flows, &{&1.name, &1.id})]}
          phx-change="select_sub_flow"
        />
      </div>

      <%= if @data["flow_id"] && @data["flow_id"] != "" do %>
        <div>
          <.field_label icon="hero-arrows-right-left" icon_color="text-accent-teal" class="mb-2">
            Input Mapping
          </.field_label>
          <p class="text-muted-caption mb-3">
            Map parent flow state/input to sub-flow payload fields
          </p>

          <%= if (@sub_flow_schema) == [] do %>
            <p class="text-muted-caption italic">
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
                <span class="text-muted-caption">({field["type"]})</span>
                <span class="text-muted-caption">&larr;</span>
              </div>
              <.code_editor_field
                id={"code-editor-#{@node_id}-mapping-#{field["name"]}"}
                value={get_in(@data, ["input_mapping", field["name"]]) || ""}
                language="elixir"
                readonly={false}
                event="update_input_mapping"
                field={field["name"]}
                class="w-full rounded-lg"
                height="36px"
                max_height=""
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
        icon_color="text-accent-orange"
      />
      <.skip_condition_fields node_id={@node_id} skip_condition={@data["skip_condition"] || ""} />
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
          icon_color="text-accent-violet"
        />
        <div>
          <.field_label icon="hero-funnel" icon_color="text-accent-teal">
            Source Expression
          </.field_label>
          <.code_editor_field
            id={"code-editor-#{@node_id}-source_expression"}
            value={@data["source_expression"] || ""}
            language="elixir"
            readonly={false}
            event="update_node_data"
            field="source_expression"
            class="w-full rounded-lg"
            height="60px"
            max_height=""
          />
        </div>
        <.prop_field
          label="Item Variable"
          field="item_variable"
          value={@data["item_variable"] || "item"}
          placeholder="item"
          icon="hero-variable"
          icon_color="text-accent-purple"
        />
        <.prop_field
          label="Accumulator Key"
          field="accumulator"
          value={@data["accumulator"] || "results"}
          placeholder="results"
          icon="hero-archive-box"
          icon_color="text-accent-amber"
        />
        <.prop_field
          label="Batch Size"
          field="batch_size"
          value={@data["batch_size"] || "10"}
          placeholder="10"
          type="number"
          icon="hero-squares-2x2"
          icon_color="text-accent-purple"
        />
        <.prop_field
          label="Timeout per Item (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "5000"}
          placeholder="5000"
          type="number"
          icon="hero-clock"
          icon_color="text-accent-orange"
        />
        <.skip_condition_fields node_id={@node_id} skip_condition={@data["skip_condition"] || ""} />
      </div>

      <div :if={@tab == "code"}>
        <.field_label icon="hero-code-bracket" icon_color="text-accent-purple">
          Body Code
        </.field_label>
        <.code_editor_field
          id={"code-editor-#{@node_id}-body_code"}
          value={@data["body_code"] || ""}
          language="elixir"
          readonly={false}
          event="update_node_data"
          field="body_code"
          class="w-full rounded-lg"
          height="200px"
          max_height=""
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
        icon_color="text-accent-violet"
      />
      <.prop_field
        label="Event Type"
        field="event_type"
        value={@data["event_type"] || ""}
        placeholder="e.g. approval, payment.confirmed"
        icon="hero-bell-alert"
        icon_color="text-accent-rose"
      />
      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "3600000"}
        placeholder="3600000"
        type="number"
        icon="hero-clock"
        icon_color="text-accent-orange"
      />
      <.prop_field
        label="Resume Path"
        field="resume_path"
        value={@data["resume_path"] || ""}
        placeholder="e.g. data.approved"
        icon="hero-arrow-right-circle"
        icon_color="text-accent-emerald"
      />
      <div>
        <.field_label icon="hero-link" icon_color="text-accent-blue">Callback URL</.field_label>
        <p class="rounded-lg border bg-muted/50 px-3 py-2 text-muted-caption font-mono">
          POST /webhook/:token/resume/{@data["event_type"] || "<event_type>"}
        </p>
      </div>
      <.skip_condition_fields node_id={@node_id} skip_condition={@data["skip_condition"] || ""} />
    </div>
    """
  end

  def node_properties(%{type: "fail"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.node_common_fields
        data={@data}
        name_default="Fail"
        name_placeholder="Fail"
        description_placeholder="When does this error occur?"
      />
      <div>
        <.field_label icon="hero-exclamation-triangle" icon_color="text-accent-red">
          Error Message
        </.field_label>
        <p class="text-muted-caption mb-1.5">
          Elixir expression with
          <.inline_code>input</.inline_code>
          and
          <.inline_code>state</.inline_code>
          bindings
        </p>
        <.code_editor_field
          id={"code-editor-#{@node_id}-message"}
          value={@data["message"] || ~S|"Error: #{input["reason"]}"|}
          language="elixir"
          readonly={false}
          event="update_node_data"
          field="message"
          class="w-full rounded-lg"
          height="100px"
          max_height=""
        />
      </div>
      <.prop_select
        label="Include State"
        field="include_state"
        value={to_string(@data["include_state"] || false)}
        options={[{"No", "false"}, {"Yes", "true"}]}
        icon="hero-document-text"
        icon_color="text-accent-amber"
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
        icon_color="text-accent-violet"
      />
      <div>
        <.field_label icon="hero-bug-ant" icon_color="text-accent-purple">Expression</.field_label>
        <p class="text-muted-caption mb-1.5">
          Elixir expression to inspect. Leave empty to log the input.
        </p>
        <.code_editor_field
          id={"code-editor-#{@node_id}-expression"}
          value={@data["expression"] || ""}
          language="elixir"
          readonly={false}
          event="update_node_data"
          field="expression"
          class="w-full rounded-lg"
          height="100px"
          max_height=""
        />
      </div>
      <.prop_select
        label="Log Level"
        field="log_level"
        value={@data["log_level"] || "info"}
        options={[{"Debug", "debug"}, {"Info", "info"}, {"Warning", "warning"}]}
        icon="hero-signal"
        icon_color="text-accent-cyan"
      />
      <.prop_field
        label="State Key"
        field="state_key"
        value={@data["state_key"] || "debug"}
        placeholder="debug"
        icon="hero-key"
        icon_color="text-accent-emerald"
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

  # ── Private helper components ─────────────────────────────────────────────

  attr :node_id, :string, required: true
  attr :skip_condition, :string, default: ""

  defp skip_condition_fields(assigns) do
    ~H"""
    <div class="border-t pt-4 mt-4">
      <.field_label icon="hero-funnel" icon_color="text-yellow-400">Skip Condition</.field_label>
      <p class="text-muted-caption mb-1.5">
        Skip this node when expression is true
      </p>
      <.code_editor_field
        id={"code-editor-#{@node_id}-skip_condition"}
        value={@skip_condition}
        language="elixir"
        readonly={false}
        event="update_node_data"
        field="skip_condition"
        class="w-full rounded-lg"
        height="60px"
        max_height=""
      />
    </div>
    """
  end

  attr :data, :map, required: true
  attr :name_default, :string, required: true
  attr :name_placeholder, :string, default: ""
  attr :description_placeholder, :string, required: true

  defp node_common_fields(assigns) do
    ~H"""
    <.prop_field
      label="Node Name"
      field="name"
      value={@data["name"] || @name_default}
      placeholder={@name_placeholder}
      icon="hero-tag"
      icon_color="text-accent-violet"
    />
    <.prop_field
      label="Description"
      field="description"
      value={@data["description"] || ""}
      placeholder={@description_placeholder}
      type="textarea"
      icon="hero-chat-bubble-bottom-center-text"
      icon_color="text-accent-sky"
    />
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
  attr :icon_color, :string, default: "text-accent-blue"

  def prop_field(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.field_label icon={@icon} icon_color={@icon_color}>{@label}</.field_label>
      <.inline_textarea
        value={@value}
        rows="3"
        placeholder={@placeholder}
        phx-blur="update_node_data"
        phx-value-field={@field}
      />
    </div>
    """
  end

  def prop_field(assigns) do
    ~H"""
    <div>
      <.field_label icon={@icon} icon_color={@icon_color}>{@label}</.field_label>
      <.inline_input
        type={@type}
        value={@value}
        placeholder={@placeholder}
        phx-blur="update_node_data"
        phx-value-field={@field}
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: ""
  attr :options, :list, required: true
  attr :icon, :string, default: nil
  attr :icon_color, :string, default: "text-accent-blue"

  def prop_select(assigns) do
    ~H"""
    <div>
      <.field_label icon={@icon} icon_color={@icon_color}>{@label}</.field_label>
      <.inline_select
        options={@options}
        value={@value}
        phx-change="update_node_data"
        phx-value-field={@field}
      />
    </div>
    """
  end

  # ── Properties tab bar ───────────────────────────────────────────────────

  attr :tabs, :list, required: true
  attr :active, :string, required: true

  def properties_tabs(assigns) do
    assigns =
      assign(assigns, :normalized_tabs, Enum.map(assigns.tabs, fn {label, id} -> {id, label} end))

    ~H"""
    <.underline_tabs
      tabs={@normalized_tabs}
      active={@active}
      click_event="set_properties_tab"
      class="-mx-4 px-4"
    />
    """
  end
end
