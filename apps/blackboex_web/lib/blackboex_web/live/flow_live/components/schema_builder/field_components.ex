defmodule BlackboexWeb.FlowLive.Components.SchemaBuilder.FieldComponents do
  @moduledoc false

  use BlackboexWeb, :html

  import BlackboexWeb.Components.UI.FieldLabel
  import BlackboexWeb.Components.UI.InlineInput
  import BlackboexWeb.Components.UI.InlineSelect
  import BlackboexWeb.Components.UI.InlineTextarea

  alias Blackboex.Flows.SchemaUtils

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

  def type_icon("string"), do: "hero-language"
  def type_icon("integer"), do: "hero-hashtag"
  def type_icon("float"), do: "hero-hashtag"
  def type_icon("boolean"), do: "hero-check-circle"
  def type_icon("array"), do: "hero-queue-list"
  def type_icon("object"), do: "hero-cube"
  def type_icon(_), do: "hero-question-mark-circle"

  def type_color("string"), do: "text-type-string-foreground"
  def type_color("integer"), do: "text-type-number-foreground"
  def type_color("float"), do: "text-type-number-foreground"
  def type_color("boolean"), do: "text-type-boolean-foreground"
  def type_color("array"), do: "text-type-array-foreground"
  def type_color("object"), do: "text-type-object-foreground"
  def type_color(_), do: "text-muted-foreground"

  @doc false
  def type_options, do: @type_options

  @doc false
  def item_type_options, do: @item_type_options

  @doc false
  def max_depth, do: @max_depth

  # ── Single field row (compact) ──

  attr :field, :map, required: true
  attr :index, :integer, required: true
  attr :schema_id, :string, required: true
  attr :path, :string, required: true
  attr :depth, :integer, required: true
  attr :show_initial_value, :boolean, default: false

  def schema_field_row(assigns) do
    field_path = SchemaUtils.build_path(assigns.path, assigns.index)
    field_type = assigns.field["type"] || "string"
    has_constraints = SchemaUtils.has_any_constraint?(assigns.field)

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
        <.inline_input
          value={@field["name"] || ""}
          placeholder="name"
          phx-blur="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          phx-value-prop="name"
          class="flex-1 min-w-0 rounded-none border-0 bg-transparent px-1 py-0 text-xs focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50"
        />

        <%!-- Type select (compact) --%>
        <.inline_select
          value={@field_type}
          options={type_options()}
          phx-change="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          phx-value-prop="type"
          class="w-auto rounded-none border-0 bg-transparent py-0 pl-0 pr-4 text-[10px] font-medium text-muted-foreground cursor-pointer focus-visible:ring-0 focus-visible:ring-offset-0"
        />

        <%!-- Required toggle (asterisk) --%>
        <.button
          type="button"
          variant="ghost"
          phx-click="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          phx-value-prop="required"
          phx-value-value={to_string(@field["required"] != true)}
          title={
            if @field["required"],
              do: "Required (click to make optional)",
              else: "Optional (click to make required)"
          }
          class={"h-auto w-auto rounded p-0.5 text-[10px] font-bold transition-colors hover:bg-transparent " <>
            if(@field["required"] == true,
              do: "text-accent-red hover:text-accent-red/80",
              else: "text-muted-foreground/30 hover:text-muted-foreground"
            )}
        >
          *
        </.button>

        <%!-- Expand constraints (gear) --%>
        <.button
          :if={@field_type in ["string", "integer", "float", "array"] or @show_initial_value}
          type="button"
          variant="ghost"
          phx-click={JS.toggle(to: "#constraints-#{@schema_id}-#{@field_path}")}
          title="Constraints"
          class={"h-auto w-auto rounded p-0.5 transition-colors hover:bg-transparent " <>
            if(@has_constraints,
              do: "text-primary hover:text-primary/80",
              else: "text-muted-foreground/40 hover:text-muted-foreground opacity-0 group-hover:opacity-100"
            )}
        >
          <.icon name="hero-adjustments-horizontal-mini" class="size-3" />
        </.button>

        <%!-- Delete --%>
        <.button
          type="button"
          variant="ghost"
          phx-click="schema_remove_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@field_path}
          class="h-auto w-auto rounded p-0.5 text-muted-foreground/40 hover:text-destructive hover:bg-transparent opacity-0 group-hover:opacity-100 transition-opacity"
        >
          <.icon name="hero-x-mark-mini" class="size-3" />
        </.button>
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

  def string_constraints(assigns) do
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
        value={SchemaUtils.format_enum(@constraints["enum"])}
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

  def number_constraints(assigns) do
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

  def array_constraints(assigns) do
    constraints = assigns.field["constraints"] || %{}
    assigns = assign(assigns, :constraints, constraints)

    ~H"""
    <div class="space-y-1.5">
      <div class="flex gap-1.5">
        <div class="flex items-center gap-1">
          <span class="text-muted-foreground">items:</span>
          <.inline_select
            value={@constraints["item_type"]}
            options={item_type_options()}
            phx-change="schema_update_constraint"
            phx-value-schema-id={@schema_id}
            phx-value-path={@path}
            phx-value-prop="item_type"
            class="w-auto rounded border-0 bg-background px-1 py-0 text-[10px] cursor-pointer focus-visible:ring-1 focus-visible:ring-primary focus-visible:ring-offset-0"
          />
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

  def nested_object_fields(assigns) do
    nested_fields = assigns.field["fields"] || []
    assigns = assign(assigns, :nested_fields, nested_fields)

    ~H"""
    <div class="ml-3 pl-2 border-l border-dashed border-border mt-0.5">
      <div class="flex items-center justify-between py-0.5 px-1">
        <span class="text-[10px] text-muted-foreground flex items-center gap-1">
          <.icon name="hero-cube-mini" class="size-2.5" /> fields
        </span>
        <.button
          type="button"
          variant="ghost"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path <> ".fields"}
          class="h-auto w-auto inline-flex items-center gap-0.5 rounded px-1 py-0 text-[10px] text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <.icon name="hero-plus-mini" class="size-2.5" />
        </.button>
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

  def nested_array_object_fields(assigns) do
    item_fields = get_in(assigns.field, ["constraints", "item_fields"]) || []
    assigns = assign(assigns, :item_fields, item_fields)

    ~H"""
    <div class="mt-1">
      <div class="flex items-center justify-between py-0.5">
        <span class="text-muted-foreground flex items-center gap-1">
          <.icon name="hero-cube-mini" class="size-2.5" /> item fields
        </span>
        <.button
          type="button"
          variant="ghost"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path <> ".constraints.item_fields"}
          class="h-auto w-auto inline-flex items-center gap-0.5 rounded px-1 py-0 text-[10px] text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <.icon name="hero-plus-mini" class="size-2.5" />
        </.button>
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

  def initial_value_input(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <span class="text-muted-foreground whitespace-nowrap">initial:</span>
      <.inline_input
        :if={@field["type"] in ["string", "integer", "float"]}
        type={if @field["type"] == "string", do: "text", else: "number"}
        value={SchemaUtils.format_initial_value(@field["initial_value"])}
        placeholder="—"
        phx-blur="schema_update_field"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop="initial_value"
        class="flex-1 rounded border bg-background px-1.5 py-0 text-[10px] focus-visible:ring-1 focus-visible:ring-primary focus-visible:ring-offset-0"
      />
      <.field_label
        :if={@field["type"] == "boolean"}
        class="flex items-center gap-1 text-[10px] text-muted-foreground mb-0"
      >
        <.input
          type="checkbox"
          checked={@field["initial_value"] == true}
          phx-click="schema_update_field"
          phx-value-schema-id={@schema_id}
          phx-value-path={@path}
          phx-value-prop="initial_value"
          phx-value-value={to_string(@field["initial_value"] != true)}
          class="rounded border-muted-foreground size-3"
        /> {to_string(@field["initial_value"] || false)}
      </.field_label>
      <.inline_textarea
        :if={@field["type"] in ["array", "object"]}
        value={SchemaUtils.format_json_value(@field["initial_value"])}
        rows="1"
        placeholder={if @field["type"] == "array", do: "[]", else: "{}"}
        phx-blur="schema_update_field"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop="initial_value"
        class="flex-1 rounded border bg-background px-1.5 py-0 text-[10px] font-mono focus-visible:ring-1 focus-visible:ring-primary focus-visible:ring-offset-0"
      />
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

  def inline_constraint(assigns) do
    ~H"""
    <div class={"flex items-center gap-1 #{@class}"}>
      <span class="text-muted-foreground whitespace-nowrap">{@label}:</span>
      <.inline_input
        type={@type}
        value={@value || ""}
        placeholder={@placeholder}
        phx-blur="schema_update_constraint"
        phx-value-schema-id={@schema_id}
        phx-value-path={@path}
        phx-value-prop={@prop}
        class="w-12 flex-1 rounded border bg-background px-1.5 py-0 text-[10px] focus-visible:ring-1 focus-visible:ring-primary focus-visible:ring-offset-0"
      />
    </div>
    """
  end
end
