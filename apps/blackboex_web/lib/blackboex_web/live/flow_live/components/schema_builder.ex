defmodule BlackboexWeb.FlowLive.Components.SchemaBuilder do
  @moduledoc """
  Reusable visual schema builder component for flow node properties.

  Renders typed fields with constraints, supports nested objects and typed arrays
  up to 3 levels deep. Used in Start (payload + state schemas) and End (response schema).
  """

  use BlackboexWeb, :html

  @type_options [
    {"String", "string"},
    {"Integer", "integer"},
    {"Float", "float"},
    {"Boolean", "boolean"},
    {"Array", "array"},
    {"Object", "object"}
  ]

  @item_type_options [
    {"String", "string"},
    {"Integer", "integer"},
    {"Float", "float"},
    {"Boolean", "boolean"},
    {"Object", "object"}
  ]

  @max_depth 3

  # ── Main component ──

  attr :schema_id, :string, required: true
  attr :fields, :list, default: []
  attr :show_initial_value, :boolean, default: false
  attr :label, :string, default: "Fields"

  @doc "Renders a schema builder with a list of fields and an 'Add Field' button."
  def schema_builder(assigns) do
    assigns = assign(assigns, :fields, assigns.fields || [])

    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <label class="text-xs font-medium text-muted-foreground">{@label}</label>
        <button
          type="button"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path=""
          class="inline-flex items-center gap-1 rounded-md border px-2 py-1 text-xs font-medium text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <.icon name="hero-plus-mini" class="size-3" /> Add Field
        </button>
      </div>

      <div :if={@fields == []} class="text-xs text-muted-foreground italic py-2">
        No fields defined. Click "Add Field" to start.
      </div>

      <div :for={{field, index} <- Enum.with_index(@fields)} class="space-y-2">
        <.schema_field_row
          field={field}
          index={index}
          schema_id={@schema_id}
          path=""
          depth={0}
          show_initial_value={@show_initial_value}
        />
      </div>
    </div>
    """
  end

  # ── Single field row ──

  attr :field, :map, required: true
  attr :index, :integer, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true
  attr :depth, :integer, required: true
  attr :show_initial_value, :boolean, default: false

  defp schema_field_row(assigns) do
    field_path = build_path(assigns.path, assigns.index)
    assigns = assign(assigns, :field_path, field_path)

    ~H"""
    <div class={"rounded-lg border bg-card p-3 space-y-2 #{if @depth > 0, do: "ml-4 border-dashed"}"}>
      <%!-- Row 1: Name + Type + Required + Remove --%>
      <div class="flex items-center gap-2">
        <input
          type="text"
          value={@field["name"] || ""}
          placeholder="field_name"
          phx-blur="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          phx-value-prop="name"
          class="flex-1 rounded-md border bg-background px-2 py-1 text-xs focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        />
        <select
          phx-change="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          phx-value-prop="type"
          class="rounded-md border bg-background px-2 py-1 text-xs focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >
          <option :for={{label, val} <- type_options()} value={val} selected={val == @field["type"]}>
            {label}
          </option>
        </select>
        <label class="flex items-center gap-1 text-xs text-muted-foreground whitespace-nowrap">
          <input
            type="checkbox"
            checked={@field["required"] == true}
            phx-click="schema_update_field"
            phx-value-schema-id={@schema_id}
            phx-value-path={@field_path}
            phx-value-prop="required"
            phx-value-value={to_string(@field["required"] != true)}
            class="rounded border-muted-foreground"
          /> Req
        </label>
        <button
          type="button"
          phx-click="schema_remove_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          class="rounded-md p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
        >
          <.icon name="hero-trash-mini" class="size-3.5" />
        </button>
      </div>

      <%!-- Row 2: Type-specific constraints --%>
      <.string_constraints
        :if={@field["type"] == "string"}
        field={@field}
        schema_id={@schema_id}
        path={@field_path}
      />
      <.number_constraints
        :if={@field["type"] in ["integer", "float"]}
        field={@field}
        schema_id={@schema_id}
        path={@field_path}
      />
      <.array_constraints
        :if={@field["type"] == "array"}
        field={@field}
        schema_id={@schema_id}
        path={@field_path}
        depth={@depth}
        show_initial_value={@show_initial_value}
      />

      <%!-- Row 3: Initial value (state schema only) --%>
      <.initial_value_input
        :if={@show_initial_value}
        field={@field}
        schema_id={@schema_id}
        path={@field_path}
      />

      <%!-- Row 4: Nested fields for object type --%>
      <.nested_object_fields
        :if={@field["type"] == "object" and @depth < @max_depth - 1}
        field={@field}
        schema_id={@schema_id}
        path={@field_path}
        depth={@depth}
        show_initial_value={@show_initial_value}
      />
    </div>
    """
  end

  # ── String constraints ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true

  defp string_constraints(assigns) do
    constraints = assigns.field["constraints"] || %{}
    assigns = assign(assigns, :constraints, constraints)

    ~H"""
    <div class="grid grid-cols-2 gap-2">
      <.constraint_input
        label="Min Length"
        prop="min_length"
        value={@constraints["min_length"]}
        type="number"
        schema_id={@schema_id}
        path={@path}
      />
      <.constraint_input
        label="Max Length"
        prop="max_length"
        value={@constraints["max_length"]}
        type="number"
        schema_id={@schema_id}
        path={@path}
      />
      <.constraint_input
        label="Pattern"
        prop="pattern"
        value={@constraints["pattern"]}
        placeholder="^[A-Z]+$"
        schema_id={@schema_id}
        path={@path}
      />
      <.constraint_input
        label="Enum (comma-sep)"
        prop="enum"
        value={format_enum(@constraints["enum"])}
        placeholder="a,b,c"
        schema_id={@schema_id}
        path={@path}
      />
    </div>
    """
  end

  # ── Number constraints ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true

  defp number_constraints(assigns) do
    constraints = assigns.field["constraints"] || %{}
    assigns = assign(assigns, :constraints, constraints)

    ~H"""
    <div class="grid grid-cols-2 gap-2">
      <.constraint_input
        label="Min"
        prop="min"
        value={@constraints["min"]}
        type="number"
        schema_id={@schema_id}
        path={@path}
      />
      <.constraint_input
        label="Max"
        prop="max"
        value={@constraints["max"]}
        type="number"
        schema_id={@schema_id}
        path={@path}
      />
    </div>
    """
  end

  # ── Array constraints ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true
  attr :depth, :integer, required: true
  attr :show_initial_value, :boolean, default: false

  defp array_constraints(assigns) do
    constraints = assigns.field["constraints"] || %{}
    assigns = assign(assigns, :constraints, constraints)

    ~H"""
    <div class="space-y-2">
      <div class="grid grid-cols-3 gap-2">
        <div>
          <label class="block text-[10px] text-muted-foreground mb-0.5">Item Type</label>
          <select
            phx-change="schema_update_constraint"
            phx-value-schema-id={@schema_id}
            phx-value-path={@path}
            phx-value-prop="item_type"
            class="w-full rounded-md border bg-background px-2 py-1 text-xs focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          >
            <option
              :for={{label, val} <- item_type_options()}
              value={val}
              selected={val == @constraints["item_type"]}
            >
              {label}
            </option>
          </select>
        </div>
        <.constraint_input
          label="Min Items"
          prop="min_items"
          value={@constraints["min_items"]}
          type="number"
          schema_id={@schema_id}
          path={@path}
        />
        <.constraint_input
          label="Max Items"
          prop="max_items"
          value={@constraints["max_items"]}
          type="number"
          schema_id={@schema_id}
          path={@path}
        />
      </div>

      <%!-- Nested fields for array of objects --%>
      <.nested_array_object_fields
        :if={@constraints["item_type"] == "object" and @depth < @max_depth - 1}
        field={@field}
        schema_id={@schema_id}
        path={@path}
        depth={@depth}
        show_initial_value={@show_initial_value}
      />
    </div>
    """
  end

  # ── Nested object fields ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true
  attr :depth, :integer, required: true
  attr :show_initial_value, :boolean, default: false

  defp nested_object_fields(assigns) do
    nested_fields = assigns.field["fields"] || []
    assigns = assign(assigns, :nested_fields, nested_fields)

    ~H"""
    <div class="space-y-2 mt-2">
      <div class="flex items-center justify-between">
        <span class="text-[10px] font-medium text-muted-foreground">Object Fields</span>
        <button
          type="button"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path <> ".fields"}
          class="inline-flex items-center gap-0.5 rounded border px-1.5 py-0.5 text-[10px] text-muted-foreground hover:bg-accent"
        >
          <.icon name="hero-plus-mini" class="size-2.5" /> Add
        </button>
      </div>
      <div :for={{nested, idx} <- Enum.with_index(@nested_fields)} class="space-y-1">
        <.schema_field_row
          field={nested}
          index={idx}
          schema_id={@schema_id}
          path={@path <> ".fields"}
          depth={@depth + 1}
          show_initial_value={@show_initial_value}
        />
      </div>
    </div>
    """
  end

  # ── Nested array object fields ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true
  attr :depth, :integer, required: true
  attr :show_initial_value, :boolean, default: false

  defp nested_array_object_fields(assigns) do
    item_fields = get_in(assigns.field, ["constraints", "item_fields"]) || []
    assigns = assign(assigns, :item_fields, item_fields)

    ~H"""
    <div class="space-y-2 mt-2">
      <div class="flex items-center justify-between">
        <span class="text-[10px] font-medium text-muted-foreground">Item Fields</span>
        <button
          type="button"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path <> ".constraints.item_fields"}
          class="inline-flex items-center gap-0.5 rounded border px-1.5 py-0.5 text-[10px] text-muted-foreground hover:bg-accent"
        >
          <.icon name="hero-plus-mini" class="size-2.5" /> Add
        </button>
      </div>
      <div :for={{item_field, idx} <- Enum.with_index(@item_fields)} class="space-y-1">
        <.schema_field_row
          field={item_field}
          index={idx}
          schema_id={@schema_id}
          path={@path <> ".constraints.item_fields"}
          depth={@depth + 1}
          show_initial_value={@show_initial_value}
        />
      </div>
    </div>
    """
  end

  # ── Initial value input ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true

  defp initial_value_input(assigns) do
    ~H"""
    <div>
      <label class="block text-[10px] text-muted-foreground mb-0.5">Initial Value</label>
      <input
        :if={@field["type"] in ["string", "integer", "float"]}
        type={if @field["type"] == "string", do: "text", else: "number"}
        value={format_initial_value(@field["initial_value"])}
        placeholder="Initial value"
        phx-blur="schema_update_field"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop="initial_value"
        class="w-full rounded-md border bg-background px-2 py-1 text-xs focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      />
      <label
        :if={@field["type"] == "boolean"}
        class="flex items-center gap-1.5 text-xs text-muted-foreground"
      >
        <input
          type="checkbox"
          checked={@field["initial_value"] == true}
          phx-click="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path}
          phx-value-prop="initial_value"
          phx-value-value={to_string(@field["initial_value"] != true)}
          class="rounded border-muted-foreground"
        /> Initial: {to_string(@field["initial_value"] || false)}
      </label>
      <textarea
        :if={@field["type"] in ["array", "object"]}
        phx-blur="schema_update_field"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop="initial_value"
        rows="2"
        placeholder={if @field["type"] == "array", do: "[]", else: "{}"}
        class="w-full rounded-md border bg-background px-2 py-1 text-xs font-mono focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      ><%= format_json_value(@field["initial_value"]) %></textarea>
    </div>
    """
  end

  # ── Constraint input (reusable) ──

  attr :label, :string, required: true
  attr :prop, :string, required: true
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :placeholder, :string, default: ""
  attr :schema_id, :string, required: true
  attr :path, :string, required: true

  defp constraint_input(assigns) do
    ~H"""
    <div>
      <label class="block text-[10px] text-muted-foreground mb-0.5">{@label}</label>
      <input
        type={@type}
        value={@value || ""}
        placeholder={@placeholder}
        phx-blur="schema_update_constraint"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop={@prop}
        class="w-full rounded-md border bg-background px-2 py-1 text-xs focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      />
    </div>
    """
  end

  # ── Response mapping component ──

  attr :mapping, :list, default: []
  attr :response_schema, :list, default: []
  attr :state_variables, :list, default: []

  @doc "Renders response field → state variable mapping dropdowns."
  def response_mapping(assigns) do
    assigns = assign(assigns, :mapping, assigns.mapping || [])

    ~H"""
    <div :if={@response_schema != []} class="space-y-2 mt-3">
      <label class="text-xs font-medium text-muted-foreground">Field → State Mapping</label>
      <div :for={field <- @response_schema} class="flex items-center gap-2">
        <span class="text-xs font-mono min-w-[80px] truncate">{field["name"]}</span>
        <.icon name="hero-arrow-right-mini" class="size-3 text-muted-foreground shrink-0" />
        <select
          phx-change="schema_update_mapping"
          phx-value-response-field={field["name"]}
          class="flex-1 rounded-md border bg-background px-2 py-1 text-xs focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >
          <option value="">— Select state variable —</option>
          <option
            :for={var <- @state_variables}
            value={var}
            selected={var == find_mapped_variable(@mapping, field["name"])}
          >
            {var}
          </option>
        </select>
      </div>
    </div>
    """
  end

  # ── Helpers ──

  defp build_path("", index), do: "#{index}"
  defp build_path(parent, index), do: "#{parent}.#{index}"

  defp format_enum(nil), do: ""
  defp format_enum(list) when is_list(list), do: Enum.join(list, ",")
  defp format_enum(_), do: ""

  defp format_initial_value(nil), do: ""
  defp format_initial_value(val), do: to_string(val)

  defp format_json_value(nil), do: ""

  defp format_json_value(val) when is_map(val) or is_list(val) do
    Jason.encode!(val, pretty: true)
  end

  defp format_json_value(val), do: to_string(val)

  defp find_mapped_variable(mapping, response_field) do
    case Enum.find(mapping, &(&1["response_field"] == response_field)) do
      nil -> ""
      entry -> entry["state_variable"]
    end
  end

  @doc false
  def type_options, do: @type_options

  @doc false
  def item_type_options, do: @item_type_options

  @doc false
  def max_depth, do: @max_depth
end
