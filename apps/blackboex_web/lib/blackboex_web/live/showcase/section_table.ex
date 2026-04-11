defmodule BlackboexWeb.Showcase.Sections.DataTable do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @sample_rows [
    %{id: 1, name: "Weather API", status: "active", calls: "12,345"},
    %{id: 2, name: "Translation API", status: "draft", calls: "0"},
    %{id: 3, name: "Image Resize API", status: "active", calls: "8,721"}
  ]

  @code_table ~S"""
  <.table id="demo" rows={@rows}>
    <:col :let={row} label="Name">{row.name}</:col>
    <:col :let={row} label="Status">{row.status}</:col>
    <:col :let={row} label="Calls">{row.calls}</:col>
    <:action :let={row}>
      <.button variant="ghost" size="compact">Edit</.button>
    </:action>
  </.table>
  """

  @code_row_click ~S"""
  <%!-- row_click: makes each row clickable --%>
  <.table id="clickable" rows={@rows}
    row_click={fn row -> JS.navigate(~p"/showcase/button") end}>
    <:col :let={row} label="Name">{row.name}</:col>
  </.table>

  <%!-- row_id: custom DOM ID for each <tr> --%>
  <.table id="with-ids" rows={@rows}
    row_id={fn row -> "row-#{row.id}" end}>
    <:col :let={row} label="Name">{row.name}</:col>
  </.table>

  <%!-- row_item: transform row before passing to slots --%>
  <.table id="mapped" rows={@rows}
    row_item={fn row -> Map.put(row, :display_name, String.upcase(row.name)) end}>
    <:col :let={row} label="Name">{row.display_name}</:col>
  </.table>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:rows, @sample_rows)
      |> assign(:code_table, @code_table)
      |> assign(:code_row_click, @code_row_click)

    ~H"""
    <.section_header
      title="Table"
      description="Data table with column slots and optional row actions. Supports LiveStream rows, row_click, row_id, and row_item."
      module="BlackboexWeb.Components.Table"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic Table" code={@code_table}>
        <.table id="showcase-table" rows={@rows}>
          <:col :let={row} label="Name">{row.name}</:col>
          <:col :let={row} label="Status">{row.status}</:col>
          <:col :let={row} label="Calls">{row.calls}</:col>
          <:action :let={_row}>
            <.button variant="ghost" size="compact">Edit</.button>
          </:action>
        </.table>
      </.showcase_block>

      <.showcase_block title="row_click (clickable rows)" code={@code_row_click}>
        <.table
          id="showcase-click-table"
          rows={@rows}
          row_click={fn _row -> JS.navigate(~p"/showcase/button") end}
        >
          <:col :let={row} label="Name">{row.name}</:col>
          <:col :let={row} label="Status">{row.status}</:col>
          <:col :let={row} label="Calls">{row.calls}</:col>
        </.table>
        <p class="mt-2 text-xs text-muted-foreground">Click any row to navigate to the Button section.</p>
      </.showcase_block>

      <.showcase_block title="row_id & row_item">
        <.table
          id="showcase-mapped-table"
          rows={@rows}
          row_id={fn row -> "demo-row-#{row.id}" end}
          row_item={fn row -> Map.put(row, :display_name, String.upcase(row.name)) end}
        >
          <:col :let={row} label="Name (uppercased via row_item)">{row.display_name}</:col>
          <:col :let={row} label="Status">{row.status}</:col>
        </.table>
      </.showcase_block>
    </div>
    """
  end
end
