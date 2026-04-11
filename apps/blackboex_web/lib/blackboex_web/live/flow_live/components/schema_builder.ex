defmodule BlackboexWeb.FlowLive.Components.SchemaBuilder do
  @moduledoc """
  Reusable visual schema builder component for flow node properties.

  Renders typed fields with constraints, supports nested objects and typed arrays
  up to 3 levels deep. Used in Start (payload + state schemas) and End (response schema).
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.UI.FieldLabel
  import BlackboexWeb.Components.UI.InlineSelect

  alias BlackboexWeb.FlowLive.Components.SchemaBuilder.FieldComponents

  import FieldComponents

  alias Blackboex.Flows.SchemaUtils

  # Re-export constants so callers that do `import SchemaBuilder` still work.
  @doc false
  defdelegate type_options, to: FieldComponents

  @doc false
  defdelegate item_type_options, to: FieldComponents

  @doc false
  defdelegate max_depth, to: FieldComponents

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
        <.field_label class="mb-0">{@label}</.field_label>
        <.button
          type="button"
          variant="ghost-muted"
          size="micro"
          phx-click="schema_add_field"
          phx-value-schema-id={@schema_id}
          phx-value-path=""
          class="font-medium"
        >
          <.icon name="hero-plus-mini" class="size-3" /> Add
        </.button>
      </div>

      <div :if={@fields == []} class="text-2xs text-muted-foreground italic py-1.5 text-center">
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

  # ── Response mapping component ──

  attr :mapping, :list, default: []
  attr :response_schema, :list, default: []
  attr :state_variables, :list, default: []

  @doc "Renders response field → state variable mapping dropdowns."
  def response_mapping(assigns) do
    assigns = assign(assigns, :mapping, assigns.mapping || [])

    ~H"""
    <div :if={@response_schema != []} class="space-y-1 mt-2">
      <.field_label class="mb-0">Field → State Mapping</.field_label>
      <div :for={field <- @response_schema} class="flex items-center gap-1.5 py-0.5">
        <span class="text-2xs font-mono text-muted-foreground min-w-[60px] truncate">
          {field["name"]}
        </span>
        <.icon name="hero-arrow-right-mini" class="size-2.5 text-muted-foreground/50 shrink-0" />
        <.inline_select
          value={SchemaUtils.find_mapped_variable(@mapping, field["name"])}
          options={[{"—", ""} | Enum.map(@state_variables, &{&1, &1})]}
          phx-change="schema_update_mapping"
          phx-value-response-field={field["name"]}
          class="flex-1 rounded-none border-0 bg-transparent py-0 pl-0 pr-4 text-2xs text-muted-foreground cursor-pointer focus-visible:ring-0 focus-visible:ring-offset-0"
        />
      </div>
    </div>
    """
  end
end
