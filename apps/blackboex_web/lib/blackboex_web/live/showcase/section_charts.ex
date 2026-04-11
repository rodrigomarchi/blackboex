defmodule BlackboexWeb.Showcase.Sections.Charts do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.Charts

  @bar_data [
    %{label: "Mon", value: 120},
    %{label: "Tue", value: 245},
    %{label: "Wed", value: 180},
    %{label: "Thu", value: 310},
    %{label: "Fri", value: 275},
    %{label: "Sat", value: 90},
    %{label: "Sun", value: 60}
  ]

  @line_data [
    %{label: "Jan", value: 400},
    %{label: "Feb", value: 620},
    %{label: "Mar", value: 530},
    %{label: "Apr", value: 780},
    %{label: "May", value: 690},
    %{label: "Jun", value: 910}
  ]

  @code_bar ~S"""
  <.bar_chart data={[
    %{label: "Mon", value: 120},
    %{label: "Tue", value: 245},
    %{label: "Wed", value: 180},
    %{label: "Thu", value: 310},
    %{label: "Fri", value: 275},
    %{label: "Sat", value: 90},
    %{label: "Sun", value: 60}
  ]} />
  """

  @code_line ~S"""
  <.line_chart data={[
    %{label: "Jan", value: 400},
    %{label: "Feb", value: 620},
    %{label: "Mar", value: 530},
    %{label: "Apr", value: 780},
    %{label: "May", value: 690},
    %{label: "Jun", value: 910}
  ]} />
  """

  @code_custom_size ~S"""
  <.bar_chart data={@data} width={400} height={200} />
  <.line_chart data={@data} width={400} height={150} />
  """

  @code_custom_color ~S"""
  <.bar_chart data={@data} color="var(--color-chart-2)" />
  <.line_chart data={@data} color="var(--color-chart-3)" />
  """

  @code_with_title ~S"""
  <.bar_chart data={@data} title="Requests per Day" />
  <.line_chart data={@data} title="Monthly Trend" />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(bar_data: @bar_data, line_data: @line_data)
      |> assign(:code_bar, @code_bar)
      |> assign(:code_line, @code_line)
      |> assign(:code_custom_size, @code_custom_size)
      |> assign(:code_custom_color, @code_custom_color)
      |> assign(:code_with_title, @code_with_title)

    ~H"""
    <.section_header
      title="Charts"
      description="Server-rendered SVG charts. bar_chart renders a vertical bar chart; line_chart renders a line/area chart. Data is a list of maps. Charts use CSS custom properties from the design token system for colors."
      module="BlackboexWeb.Components.Shared.Charts"
    />
    <div class="space-y-10">
      <.showcase_block title="Bar Chart" code={@code_bar}>
        <.bar_chart data={@bar_data} />
      </.showcase_block>

      <.showcase_block title="Line Chart" code={@code_line}>
        <.line_chart data={@line_data} />
      </.showcase_block>

      <.showcase_block title="Custom Width / Height" code={@code_custom_size}>
        <div class="space-y-4">
          <.bar_chart data={@bar_data} width={400} height={200} />
          <.line_chart data={@line_data} width={400} height={150} />
        </div>
      </.showcase_block>

      <.showcase_block title="Custom Color" code={@code_custom_color}>
        <div class="space-y-4">
          <.bar_chart data={@bar_data} color="var(--color-chart-2)" />
          <.line_chart data={@line_data} color="var(--color-chart-3)" />
        </div>
      </.showcase_block>

      <.showcase_block title="With Title" code={@code_with_title}>
        <div class="space-y-4">
          <.bar_chart data={@bar_data} title="Requests per Day" />
          <.line_chart data={@line_data} title="Monthly Trend" />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
