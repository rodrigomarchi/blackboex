defmodule BlackboexWeb.Showcase.Sections.FileTree do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Editor.FileTree

  @code_basic ~S"""
  <div class="h-64 rounded-lg overflow-hidden border">
    <.file_tree files={[
      %{path: "handler.ex", file_type: "source", read_only: false},
      %{path: "request.ex", file_type: "source", read_only: false},
      %{path: "response.ex", file_type: "source", read_only: false}
    ]} />
  </div>
  """

  @code_selected ~S"""
  <div class="h-64 rounded-lg overflow-hidden border">
    <.file_tree
      files={[
        %{path: "handler.ex", file_type: "source", read_only: false},
        %{path: "request.ex", file_type: "source", read_only: false},
        %{path: "response.ex", file_type: "source", read_only: false}
      ]}
      selected_path="handler.ex"
    />
  </div>
  """

  @code_generating ~S"""
  <div class="h-64 rounded-lg overflow-hidden border">
    <.file_tree
      files={[
        %{path: "handler.ex", file_type: "source", read_only: false},
        %{path: "request.ex", file_type: "source", read_only: false},
        %{path: "response.ex", file_type: "source", read_only: false}
      ]}
      generating={true}
    />
  </div>
  """

  @code_nested ~S"""
  <div class="h-64 rounded-lg overflow-hidden border">
    <.file_tree files={[
      %{path: "handler.ex", file_type: "source", read_only: false},
      %{path: "request.ex", file_type: "source", read_only: false},
      %{path: "response.ex", file_type: "source", read_only: false},
      %{path: "tests/handler_test.exs", file_type: "test", read_only: false},
      %{path: "tests/request_test.exs", file_type: "test", read_only: false}
    ]} />
  </div>
  """

  @code_empty ~S"""
  <div class="h-32 rounded-lg overflow-hidden border">
    <.file_tree files={[]} />
  </div>
  """

  @flat_files [
    %{path: "handler.ex", file_type: "source", read_only: false},
    %{path: "request.ex", file_type: "source", read_only: false},
    %{path: "response.ex", file_type: "source", read_only: false}
  ]

  @nested_files [
    %{path: "handler.ex", file_type: "source", read_only: false},
    %{path: "request.ex", file_type: "source", read_only: false},
    %{path: "response.ex", file_type: "source", read_only: false},
    %{path: "tests/handler_test.exs", file_type: "test", read_only: false},
    %{path: "tests/request_test.exs", file_type: "test", read_only: false}
  ]

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_basic, @code_basic)
      |> assign(:code_selected, @code_selected)
      |> assign(:code_generating, @code_generating)
      |> assign(:code_nested, @code_nested)
      |> assign(:code_empty, @code_empty)
      |> assign(:flat_files, @flat_files)
      |> assign(:nested_files, @nested_files)

    ~H"""
    <.section_header
      title="FileTree"
      description="File tree navigator for the API code editor. Renders a hierarchical file tree with folder/file icons. Supports selection highlighting and a generating animation state."
      module="BlackboexWeb.Components.Editor.FileTree"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic file tree" code={@code_basic}>
        <div class="h-64 rounded-lg overflow-hidden border">
          <.file_tree files={@flat_files} />
        </div>
      </.showcase_block>

      <.showcase_block title="With selected file" code={@code_selected}>
        <div class="h-64 rounded-lg overflow-hidden border">
          <.file_tree files={@flat_files} selected_path="handler.ex" />
        </div>
      </.showcase_block>

      <.showcase_block title="Generating state" code={@code_generating}>
        <div class="h-64 rounded-lg overflow-hidden border">
          <.file_tree files={@flat_files} generating={true} />
        </div>
      </.showcase_block>

      <.showcase_block title="Nested structure (with tests/ directory)" code={@code_nested}>
        <div class="h-64 rounded-lg overflow-hidden border">
          <.file_tree files={@nested_files} />
        </div>
      </.showcase_block>

      <.showcase_block title="Empty tree" code={@code_empty}>
        <div class="h-32 rounded-lg overflow-hidden border">
          <.file_tree files={[]} />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
