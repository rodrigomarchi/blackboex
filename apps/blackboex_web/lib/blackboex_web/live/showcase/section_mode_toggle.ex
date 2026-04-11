defmodule BlackboexWeb.Showcase.Sections.ModeToggle do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.ModeToggle

  @code_basic ~S"""
  <.mode_toggle
    options={[
      {"template", "Template", "hero-squares-2x2"},
      {"blank", "Blank", "hero-document"}
    ]}
    active="template"
    click_event="set_mode"
  />
  """

  @code_three ~S"""
  <.mode_toggle
    options={[
      {"view", "View", "hero-eye"},
      {"edit", "Edit", "hero-pencil"},
      {"preview", "Preview", "hero-play"}
    ]}
    active="edit"
    click_event="set_mode"
  />
  """

  @code_active_states ~S"""
  <%# First option active %>
  <.mode_toggle options={@options} active="template" click_event="set_mode" />
  <%# Second option active %>
  <.mode_toggle options={@options} active="describe" click_event="set_mode" />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_basic, @code_basic)
      |> assign(:code_three, @code_three)
      |> assign(:code_active_states, @code_active_states)

    ~H"""
    <.section_header
      title="Mode Toggle"
      description="Segmented control for mode/view switching. Renders a group of options where one is active. Triggers click_event with the selected value."
      module="BlackboexWeb.Components.Shared.ModeToggle"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic Mode Toggle (2 options)" code={@code_basic}>
        <.mode_toggle
          options={[
            {"template", "Template", "hero-squares-2x2"},
            {"blank", "Blank", "hero-document"}
          ]}
          active="template"
          click_event="set_mode"
        />
      </.showcase_block>

      <.showcase_block title="3 Options (View / Edit / Preview)" code={@code_three}>
        <.mode_toggle
          options={[
            {"view", "View", "hero-eye"},
            {"edit", "Edit", "hero-pencil"},
            {"preview", "Preview", "hero-play"}
          ]}
          active="edit"
          click_event="set_mode"
        />
      </.showcase_block>

      <.showcase_block title="Different Active States" code={@code_active_states}>
        <div class="space-y-3">
          <div>
            <p class="text-xs text-muted-foreground mb-1">active="template"</p>
            <.mode_toggle
              options={[
                {"template", "From Template", "hero-squares-2x2"},
                {"describe", "Describe It", "hero-chat-bubble-left-ellipsis"}
              ]}
              active="template"
              click_event="set_mode"
            />
          </div>
          <div>
            <p class="text-xs text-muted-foreground mb-1">active="describe"</p>
            <.mode_toggle
              options={[
                {"template", "From Template", "hero-squares-2x2"},
                {"describe", "Describe It", "hero-chat-bubble-left-ellipsis"}
              ]}
              active="describe"
              click_event="set_mode"
            />
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
