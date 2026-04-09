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

  # ── Type icon helpers ──

  defp type_icon("string"), do: "hero-language"
  defp type_icon("integer"), do: "hero-hashtag"
  defp type_icon("float"), do: "hero-hashtag"
  defp type_icon("boolean"), do: "hero-check-circle"
  defp type_icon("array"), do: "hero-queue-list"
  defp type_icon("object"), do: "hero-cube"
  defp type_icon(_), do: "hero-question-mark-circle"

  defp type_color("string"), do: "text-emerald-500"
  defp type_color("integer"), do: "text-blue-500"
  defp type_color("float"), do: "text-blue-500"
  defp type_color("boolean"), do: "text-amber-500"
  defp type_color("array"), do: "text-purple-500"
  defp type_color("object"), do: "text-indigo-500"
  defp type_color(_), do: "text-muted-foreground"

  # ── Main component ──

  attr :schema_id, :string, required: true
  attr :fields, :list, default: []
  attr :show_initial_value, :boolean, default: false
  attr :label, :string, default: "Fields"

  @doc "Renders a schema builder with a list of fields and an 'Add Field' button."
  def schema_builder(assigns) do
    assigns = assign(assigns, :fields, assigns.fields || [])

    ~H"""
    <div class="space-y-1">
      <div class="flex items-center justify-between mb-1">
        <label class="text-xs font-medium text-muted-foreground">{@label}</label>
        <button
          type="button"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path=""
          class="inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <.icon name="hero-plus-mini" class="size-3" /> Add
        </button>
      </div>

      <div :if={@fields == []} class="text-[10px] text-muted-foreground italic py-1.5 text-center">
        No fields defined
      </div>

      <div class="space-y-0.5">
        <.schema_field_row
          :for={{field, index} <- Enum.with_index(@fields)}
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

  # ── Single field row (compact) ──

  attr :field, :map, required: true
  attr :index, :integer, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true
  attr :depth, :integer, required: true
  attr :show_initial_value, :boolean, default: false

  defp schema_field_row(assigns) do
    field_path = build_path(assigns.path, assigns.index)
    field_type = assigns.field["type"] || "string"
    has_constraints = has_any_constraint?(assigns.field)

    assigns =
      assigns
      |> assign(:field_path, field_path)
      |> assign(:field_type, field_type)
      |> assign(:has_constraints, has_constraints)

    ~H"""
    <div class={"#{if @depth > 0, do: "ml-3 pl-2 border-l border-dashed border-border"}"}>
      <%!-- Compact row: icon + name + type + required + actions --%>
      <div class="group flex items-center gap-1.5 rounded-md px-1.5 py-1 hover:bg-accent/50">
        <%!-- Type icon --%>
        <.icon name={type_icon(@field_type)} class={"size-3.5 shrink-0 #{type_color(@field_type)}"} />

        <%!-- Field name --%>
        <input
          type="text"
          value={@field["name"] || ""}
          placeholder="name"
          phx-blur="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          phx-value-prop="name"
          class="flex-1 min-w-0 bg-transparent px-1 py-0 text-xs border-0 focus:outline-none focus:ring-0 placeholder:text-muted-foreground/50"
        />

        <%!-- Type select (compact) --%>
        <select
          phx-change="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          phx-value-prop="type"
          class="rounded border-0 bg-transparent py-0 pl-0 pr-4 text-[10px] font-medium text-muted-foreground focus:outline-none focus:ring-0 cursor-pointer"
        >
          <option :for={{label, val} <- type_options()} value={val} selected={val == @field_type}>
            {label}
          </option>
        </select>

        <%!-- Required toggle (asterisk) --%>
        <button
          type="button"
          phx-click="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          phx-value-prop="required"
          phx-value-value={to_string(@field["required"] != true)}
          title={if @field["required"], do: "Required (click to make optional)", else: "Optional (click to make required)"}
          class={"rounded p-0.5 text-[10px] font-bold transition-colors " <>
            if(@field["required"] == true,
              do: "text-red-400 hover:text-red-300",
              else: "text-muted-foreground/30 hover:text-muted-foreground"
            )}
        >
          *
        </button>

        <%!-- Expand constraints (gear) --%>
        <button
          :if={@field_type in ["string", "integer", "float", "array"] or @show_initial_value}
          type="button"
          phx-click={JS.toggle(to: "#constraints-#{@schema_id}-#{@field_path}")}
          title="Constraints"
          class={"rounded p-0.5 transition-colors " <>
            if(@has_constraints,
              do: "text-primary hover:text-primary/80",
              else: "text-muted-foreground/40 hover:text-muted-foreground opacity-0 group-hover:opacity-100"
            )}
        >
          <.icon name="hero-adjustments-horizontal-mini" class="size-3" />
        </button>

        <%!-- Delete --%>
        <button
          type="button"
          phx-click="schema_remove_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          class="rounded p-0.5 text-muted-foreground/40 hover:text-destructive opacity-0 group-hover:opacity-100 transition-opacity"
        >
          <.icon name="hero-x-mark-mini" class="size-3" />
        </button>
      </div>

      <%!-- Collapsible constraints panel --%>
      <div
        :if={@field_type in ["string", "integer", "float", "array"] or @show_initial_value}
        id={"constraints-#{@schema_id}-#{@field_path}"}
        class={"ml-5 mr-1 mb-1 mt-0.5 rounded-md bg-accent/30 p-2 space-y-2 text-[10px] " <> if(@has_constraints, do: "", else: "hidden")}
      >
        <.string_constraints
          :if={@field_type == "string"}
          field={@field}
          schema_id={@schema_id}
          path={@field_path}
        />
        <.number_constraints
          :if={@field_type in ["integer", "float"]}
          field={@field}
          schema_id={@schema_id}
          path={@field_path}
        />
        <.array_constraints
          :if={@field_type == "array"}
          field={@field}
          schema_id={@schema_id}
          path={@field_path}
          depth={@depth}
          show_initial_value={@show_initial_value}
        />
        <.initial_value_input
          :if={@show_initial_value}
          field={@field}
          schema_id={@schema_id}
          path={@field_path}
        />
      </div>

      <%!-- Nested fields for object type --%>
      <.nested_object_fields
        :if={@field_type == "object" and @depth < @max_depth - 1}
        field={@field}
        schema_id={@schema_id}
        path={@field_path}
        depth={@depth}
        show_initial_value={@show_initial_value}
      />
    </div>
    """
  end

  # ── String constraints (inline) ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true

  defp string_constraints(assigns) do
    constraints = assigns.field["constraints"] || %{}
    assigns = assign(assigns, :constraints, constraints)

    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <.inline_constraint
        label="min"
        prop="min_length"
        value={@constraints["min_length"]}
        type="number"
        schema_id={@schema_id}
        path={@path}
      />
      <.inline_constraint
        label="max"
        prop="max_length"
        value={@constraints["max_length"]}
        type="number"
        schema_id={@schema_id}
        path={@path}
      />
      <.inline_constraint
        label="pattern"
        prop="pattern"
        value={@constraints["pattern"]}
        placeholder="regex"
        schema_id={@schema_id}
        path={@path}
        class="flex-1 min-w-[100px]"
      />
      <.inline_constraint
        label="enum"
        prop="enum"
        value={format_enum(@constraints["enum"])}
        placeholder="a,b,c"
        schema_id={@schema_id}
        path={@path}
        class="flex-1 min-w-[100px]"
      />
    </div>
    """
  end

  # ── Number constraints (inline) ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true

  defp number_constraints(assigns) do
    constraints = assigns.field["constraints"] || %{}
    assigns = assign(assigns, :constraints, constraints)

    ~H"""
    <div class="flex gap-1.5">
      <.inline_constraint
        label="min"
        prop="min"
        value={@constraints["min"]}
        type="number"
        schema_id={@schema_id}
        path={@path}
      />
      <.inline_constraint
        label="max"
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
    <div class="space-y-1.5">
      <div class="flex gap-1.5">
        <div class="flex items-center gap-1">
          <span class="text-muted-foreground">items:</span>
          <select
            phx-change="schema_update_constraint"
            phx-value-schema-id={@schema_id}
            phx-value-path={@path}
            phx-value-prop="item_type"
            class="rounded border-0 bg-background px-1 py-0 text-[10px] focus:outline-none focus:ring-1 focus:ring-primary cursor-pointer"
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
        <.inline_constraint
          label="min"
          prop="min_items"
          value={@constraints["min_items"]}
          type="number"
          schema_id={@schema_id}
          path={@path}
        />
        <.inline_constraint
          label="max"
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
    <div class="ml-3 pl-2 border-l border-dashed border-border mt-0.5">
      <div class="flex items-center justify-between py-0.5 px-1">
        <span class="text-[10px] text-muted-foreground flex items-center gap-1">
          <.icon name="hero-cube-mini" class="size-2.5" /> fields
        </span>
        <button
          type="button"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path <> ".fields"}
          class="inline-flex items-center gap-0.5 rounded px-1 py-0 text-[10px] text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <.icon name="hero-plus-mini" class="size-2.5" />
        </button>
      </div>
      <.schema_field_row
        :for={{nested, idx} <- Enum.with_index(@nested_fields)}
        field={nested}
        index={idx}
        schema_id={@schema_id}
        path={@path <> ".fields"}
        depth={@depth + 1}
        show_initial_value={@show_initial_value}
      />
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
    <div class="mt-1">
      <div class="flex items-center justify-between py-0.5">
        <span class="text-muted-foreground flex items-center gap-1">
          <.icon name="hero-cube-mini" class="size-2.5" /> item fields
        </span>
        <button
          type="button"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path <> ".constraints.item_fields"}
          class="inline-flex items-center gap-0.5 rounded px-1 py-0 text-[10px] text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <.icon name="hero-plus-mini" class="size-2.5" />
        </button>
      </div>
      <.schema_field_row
        :for={{item_field, idx} <- Enum.with_index(@item_fields)}
        field={item_field}
        index={idx}
        schema_id={@schema_id}
        path={@path <> ".constraints.item_fields"}
        depth={@depth + 1}
        show_initial_value={@show_initial_value}
      />
    </div>
    """
  end

  # ── Initial value input ──

  attr :field, :map, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true

  defp initial_value_input(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <span class="text-muted-foreground whitespace-nowrap">initial:</span>
      <input
        :if={@field["type"] in ["string", "integer", "float"]}
        type={if @field["type"] == "string", do: "text", else: "number"}
        value={format_initial_value(@field["initial_value"])}
        placeholder="—"
        phx-blur="schema_update_field"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop="initial_value"
        class="flex-1 rounded border bg-background px-1.5 py-0 text-[10px] focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      />
      <label
        :if={@field["type"] == "boolean"}
        class="flex items-center gap-1 text-[10px] text-muted-foreground"
      >
        <input
          type="checkbox"
          checked={@field["initial_value"] == true}
          phx-click="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path}
          phx-value-prop="initial_value"
          phx-value-value={to_string(@field["initial_value"] != true)}
          class="rounded border-muted-foreground size-3"
        /> {to_string(@field["initial_value"] || false)}
      </label>
      <textarea
        :if={@field["type"] in ["array", "object"]}
        phx-blur="schema_update_field"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop="initial_value"
        rows="1"
        placeholder={if @field["type"] == "array", do: "[]", else: "{}"}
        class="flex-1 rounded border bg-background px-1.5 py-0 text-[10px] font-mono focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      ><%= format_json_value(@field["initial_value"]) %></textarea>
    </div>
    """
  end

  # ── Inline constraint input (compact) ──

  attr :label, :string, required: true
  attr :prop, :string, required: true
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :placeholder, :string, default: ""
  attr :schema_id, :string, required: true
  attr :path, :string, required: true
  attr :class, :string, default: ""

  defp inline_constraint(assigns) do
    ~H"""
    <div class={"flex items-center gap-1 #{@class}"}>
      <span class="text-muted-foreground whitespace-nowrap">{@label}:</span>
      <input
        type={@type}
        value={@value || ""}
        placeholder={@placeholder}
        phx-blur="schema_update_constraint"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop={@prop}
        class="w-12 flex-1 rounded border bg-background px-1.5 py-0 text-[10px] focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
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
    <div :if={@response_schema != []} class="space-y-1 mt-2">
      <label class="text-xs font-medium text-muted-foreground">Field → State Mapping</label>
      <div :for={field <- @response_schema} class="flex items-center gap-1.5 py-0.5">
        <span class="text-[10px] font-mono text-muted-foreground min-w-[60px] truncate">
          {field["name"]}
        </span>
        <.icon name="hero-arrow-right-mini" class="size-2.5 text-muted-foreground/50 shrink-0" />
        <select
          phx-change="schema_update_mapping"
          phx-value-response-field={field["name"]}
          class="flex-1 rounded border-0 bg-transparent py-0 pl-0 pr-4 text-[10px] text-muted-foreground focus:outline-none focus:ring-0 cursor-pointer"
        >
          <option value="">—</option>
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

  defp has_any_constraint?(field) do
    constraints = field["constraints"] || %{}

    Enum.any?(constraints, fn {key, val} ->
      key != "item_type" and val != nil and val != "" and val != []
    end)
  end

  @doc false
  def type_options, do: @type_options

  @doc false
  def item_type_options, do: @item_type_options

  @doc false
  def max_depth, do: @max_depth
end
