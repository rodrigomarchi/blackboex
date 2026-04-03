defmodule BlackboexWeb.Components.FormField do
  @moduledoc """
  Form-aware input component with label, error messages, and Phoenix.HTML.FormField integration.

  Handles checkbox, select, textarea, and all standard HTML input types.
  For a raw `<input>` without form integration, use `BlackboexWeb.Components.Input`.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input field={@form[:role]} type="select" options={["Admin": "admin", "User": "user"]} />
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon
  alias BlackboexWeb.Components.Helpers
  alias Phoenix.HTML.Form

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &Helpers.translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label class="flex items-center gap-2 text-sm">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "h-4 w-4 rounded border-border text-primary focus:ring-ring"}
          {@rest}
        />{@label}
      </label>
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label class="block">
        <span :if={@label} class="mb-1 block text-sm font-medium text-foreground">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring",
            @errors != [] && (@error_class || "border-destructive focus:ring-destructive")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label class="block">
        <span :if={@label} class="mb-1 block text-sm font-medium text-foreground">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring resize-none",
            @errors != [] && (@error_class || "border-destructive focus:ring-destructive")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="mb-2">
      <label class="block">
        <span :if={@label} class="mb-1 block text-sm font-medium text-foreground">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class ||
              "w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring",
            @errors != [] && (@error_class || "border-destructive focus:ring-destructive")
          ]}
          {@rest}
        />
      </label>
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
    </div>
    """
  end

  defp field_error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-destructive">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end
end
