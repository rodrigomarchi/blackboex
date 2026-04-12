defmodule BlackboexWeb.Showcase.Sections.Input do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Label
  import BlackboexWeb.Components.UI.FieldLabel

  alias BlackboexWeb.Components.Input

  @code_raw_input ~S"""
  <%!-- Raw Input (BlackboexWeb.Components.Input) --%>
  <.raw_input type="text" name="name" value="" placeholder="Text" />
  <.raw_input type="email" name="email" value="" placeholder="Email" />
  <.raw_input type="password" name="pw" value="" placeholder="Password" />
  <.raw_input type="number" name="qty" value="42" />
  <.raw_input type="text" name="prefilled" default-value="Prefilled" />
  <.raw_input type="text" name="off" value="" disabled placeholder="Disabled" />
  """

  @code_form_field ~S"""
  <%!-- FormField (BlackboexWeb.Components.FormField) --%>
  <%!-- Auto-imported as .input — wraps Phoenix form fields with label + errors --%>
  <.input field={@form[:name]} type="text" label="Name" placeholder="Enter name" />
  <.input field={@form[:role]} type="select" label="Role"
    options={[{"Admin", "admin"}, {"User", "user"}]} />
  <.input field={@form[:bio]} type="textarea" label="Bio" />
  <.input field={@form[:active]} type="checkbox" label="Active" />
  """

  # Alias the raw Input to avoid conflict with FormField's auto-imported input/1
  defp raw_input(assigns) do
    Input.input(assigns)
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_raw_input, @code_raw_input)
      |> assign(:code_form_field, @code_form_field)

    ~H"""
    <.section_header
      title="Input"
      description="Two input components: raw Input (unstyled HTML input) and FormField (form-aware wrapper with label, errors, and type variants)."
      module="BlackboexWeb.Components.Input + BlackboexWeb.Components.FormField"
    />
    <div class="space-y-10 max-w-xl">
      <.showcase_block title="Raw Input (BlackboexWeb.Components.Input)" code={@code_raw_input}>
        <p class="text-xs text-muted-foreground mb-3">
          Renders a plain &lt;input&gt; element with no label or error handling.
          Use for standalone inputs outside of forms.
        </p>
        <div class="space-y-3">
          <.raw_input type="text" name="example_text" value="" placeholder="Text input" />
          <.raw_input type="email" name="example_email" value="" placeholder="Email address" />
          <.raw_input type="password" name="example_pw" value="" placeholder="Password" />
          <.raw_input type="number" name="example_num" value="42" />
          <.raw_input type="text" name="example_prefill" default-value="Prefilled via default-value" />
          <.raw_input type="text" name="example_disabled" value="" disabled placeholder="Disabled" />
          <.raw_input type="hidden" name="example_hidden" value="secret" />
        </div>
      </.showcase_block>

      <.showcase_block title="FormField (BlackboexWeb.Components.FormField)" code={@code_form_field}>
        <p class="text-xs text-muted-foreground mb-3">
          Form-aware component auto-imported as <code class="text-xs">.input</code>.
          Wraps Phoenix form fields with label, error messages, and supports
          checkbox, select, textarea, and all HTML input types.
        </p>
        <div class="space-y-3">
          <.input type="text" name="ff_name" value="" label="Name" placeholder="Enter name" />
          <.input
            type="select"
            name="ff_role"
            value="user"
            label="Role"
            options={[{"Admin", "admin"}, {"User", "user"}]}
          />
          <.input
            type="textarea"
            name="ff_bio"
            value=""
            label="Bio"
            placeholder="Tell us about yourself..."
          />
          <.input type="checkbox" name="ff_active" value="true" label="Active" />
          <.input type="text" name="ff_error" value="" label="With Error" errors={["is required"]} />
        </div>
      </.showcase_block>

      <.showcase_block title="With Label">
        <div class="space-y-1">
          <.label for="demo1">Field Label</.label>
          <.raw_input type="text" id="demo1" name="demo1" value="" placeholder="Input with label" />
        </div>
      </.showcase_block>

      <.showcase_block title="With FieldLabel (icon)">
        <div class="space-y-2">
          <.field_label icon="hero-key" icon_color="text-accent-amber">API Key Name</.field_label>
          <.raw_input type="text" name="key_name" value="" placeholder="My API Key" />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
