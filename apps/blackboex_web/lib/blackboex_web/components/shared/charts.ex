defmodule BlackboexWeb.Components.Shared.Charts do
  @moduledoc """
  Reusable SVG chart components for analytics dashboards.
  Pure server-side rendering — zero JavaScript dependencies.
  """

  use Phoenix.Component

  @doc """
  Renders a bar chart with the given data points.

  ## Assigns
    * `data` - list of `%{label: String.t(), value: number()}`
    * `title` - chart title
    * `width` - SVG width (default 600)
    * `height` - SVG height (default 300)
    * `color` - bar color (default "var(--color-chart-1)")
  """
  attr :data, :list, required: true
  attr :title, :string, default: ""
  attr :width, :integer, default: 600
  attr :height, :integer, default: 300
  attr :color, :string, default: "var(--color-chart-1)"

  @spec bar_chart(map()) :: Phoenix.LiveView.Rendered.t()
  def bar_chart(assigns) do
    max_val = assigns.data |> Enum.map(& &1.value) |> Enum.max(fn -> 1 end)
    bar_count = length(assigns.data)
    chart_height = assigns.height - 40
    bar_width = if bar_count > 0, do: max((assigns.width - 60) / bar_count - 4, 2), else: 0

    bars =
      assigns.data
      |> Enum.with_index()
      |> Enum.map(fn {point, i} ->
        bar_height = if max_val > 0, do: point.value / max_val * chart_height, else: 0
        x = 50 + i * (bar_width + 4)
        y = chart_height - bar_height + 20

        %{
          x: x,
          y: y,
          width: bar_width,
          height: bar_height,
          label: point.label,
          value: point.value
        }
      end)

    assigns = assign(assigns, bars: bars, chart_height: chart_height)

    ~H"""
    <div class="w-full">
      <p :if={@title != ""} class="text-sm font-medium text-muted-foreground mb-2">{@title}</p>
      <svg viewBox={"0 0 #{@width} #{@height}"} class="w-full" role="img">
        <rect
          :for={bar <- @bars}
          x={bar.x}
          y={bar.y}
          width={bar.width}
          height={bar.height}
          fill={@color}
          rx="2"
        >
          <title>{bar.label}: {bar.value}</title>
        </rect>
        <line
          x1="50"
          y1={@chart_height + 20}
          x2={@width - 10}
          y2={@chart_height + 20}
          stroke="var(--color-chart-axis)"
          stroke-width="1"
        />
      </svg>
    </div>
    """
  end

  @doc """
  Renders a line chart with the given data points.

  ## Assigns
    * `data` - list of `%{label: String.t(), value: number()}`
    * `title` - chart title
    * `width` - SVG width (default 600)
    * `height` - SVG height (default 300)
    * `color` - line color (default "var(--color-chart-1)")
  """
  attr :data, :list, required: true
  attr :title, :string, default: ""
  attr :width, :integer, default: 600
  attr :height, :integer, default: 300
  attr :color, :string, default: "var(--color-chart-1)"

  @spec line_chart(map()) :: Phoenix.LiveView.Rendered.t()
  def line_chart(assigns) do
    max_val = assigns.data |> Enum.map(& &1.value) |> Enum.max(fn -> 1 end)
    chart_height = assigns.height - 40
    count = length(assigns.data)
    step = if count > 1, do: (assigns.width - 70) / (count - 1), else: 0

    points =
      assigns.data
      |> Enum.with_index()
      |> Enum.map(fn {point, i} ->
        x = 50 + i * step

        y =
          if max_val > 0,
            do: chart_height - point.value / max_val * chart_height + 20,
            else: chart_height + 20

        {x, y}
      end)

    polyline_points = Enum.map_join(points, " ", fn {x, y} -> "#{x},#{y}" end)

    assigns =
      assign(assigns,
        polyline_points: polyline_points,
        points: points,
        chart_height: chart_height
      )

    ~H"""
    <div class="w-full">
      <p :if={@title != ""} class="text-sm font-medium text-muted-foreground mb-2">{@title}</p>
      <svg viewBox={"0 0 #{@width} #{@height}"} class="w-full" role="img">
        <polyline
          points={@polyline_points}
          fill="none"
          stroke={@color}
          stroke-width="2"
          stroke-linejoin="round"
        />
        <circle
          :for={{x, y} <- @points}
          cx={x}
          cy={y}
          r="3"
          fill={@color}
        />
        <line
          x1="50"
          y1={@chart_height + 20}
          x2={@width - 10}
          y2={@chart_height + 20}
          stroke="var(--color-chart-axis)"
          stroke-width="1"
        />
      </svg>
    </div>
    """
  end
end
