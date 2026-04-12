defmodule BlackboexWeb.Showcase.Sections.EditorOverview do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @components [
    %{
      name: "CodeViewer",
      module: "BlackboexWeb.Components.Editor.CodeViewer",
      description: "Syntax-highlighted code display with line numbers and Monokai dark theme.",
      complex: false
    },
    %{
      name: "CodeLabel",
      module: "BlackboexWeb.Components.Editor.CodeLabel",
      description: "Pill label for code sections and file tabs. Two variants: default and dark.",
      complex: false
    },
    %{
      name: "ValidationDashboard",
      module: "BlackboexWeb.Components.Editor.ValidationDashboard",
      description:
        "API code quality check results panel. Shows compilation, format, Credo, and test results.",
      complex: false
    },
    %{
      name: "StatusBar",
      module: "BlackboexWeb.Components.Editor.StatusBar",
      description: "Editor bottom status bar showing API name, version, and deployment status.",
      complex: false
    },
    %{
      name: "FileTree",
      module: "BlackboexWeb.Components.Editor.FileTree",
      description:
        "File navigator for the API code workspace. Hierarchical with folder/file icons and selection state.",
      complex: false
    },
    %{
      name: "Toolbar",
      module: "BlackboexWeb.Components.Editor.Toolbar",
      description: "Editor action toolbar with generate, compile, and publish controls.",
      complex: true
    },
    %{
      name: "BottomPanel",
      module: "BlackboexWeb.Components.Editor.BottomPanel",
      description: "Editor bottom panel showing logs, output, and validation results.",
      complex: true
    },
    %{
      name: "RightPanel",
      module: "BlackboexWeb.Components.Editor.RightPanel",
      description: "Collapsible right panel for validation, docs, and settings.",
      complex: true
    },
    %{
      name: "ChatPanel",
      module: "BlackboexWeb.Components.Editor.ChatPanel",
      description: "AI chat panel for code generation and editing instructions.",
      complex: true
    },
    %{
      name: "RequestBuilder",
      module: "BlackboexWeb.Components.Editor.RequestBuilder",
      description: "HTTP request tester for live API testing inside the editor.",
      complex: true
    },
    %{
      name: "ResponseViewer",
      module: "BlackboexWeb.Components.Editor.ResponseViewer",
      description: "HTTP response display with status, headers, and body rendering.",
      complex: true
    },
    %{
      name: "CommandPalette",
      module: "BlackboexWeb.Components.Editor.CommandPalette",
      description: "Keyboard-driven command search overlay for editor actions.",
      complex: true
    }
  ]

  def render(assigns) do
    assigns = assign(assigns, :components, @components)

    ~H"""
    <.section_header
      title="Editor Components"
      description="Components that form the API code editor interface at /apis/:id/edit. Components marked as complex require full editor context with LiveView socket assigns and event handlers."
      module="BlackboexWeb.Components.Editor.*"
    />
    <div class="space-y-10">
      <.showcase_block title="Component catalog">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div
            :for={comp <- @components}
            class={[
              "rounded-lg border p-4 space-y-1.5",
              if(comp.complex, do: "bg-muted/30 border-dashed", else: "bg-card")
            ]}
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm font-semibold">{comp.name}</span>
              <span
                :if={comp.complex}
                class="text-2xs font-medium uppercase tracking-wider text-muted-foreground bg-muted px-1.5 py-0.5 rounded"
              >
                complex
              </span>
              <span
                :if={!comp.complex}
                class="text-2xs font-medium uppercase tracking-wider text-success-foreground bg-success/10 px-1.5 py-0.5 rounded"
              >
                showcased
              </span>
            </div>
            <p class="text-xs text-muted-foreground">{comp.description}</p>
            <p class="text-2xs font-mono text-muted-foreground/50">{comp.module}</p>
            <p :if={comp.complex} class="text-2xs text-muted-foreground/60 italic">
              Requires full editor context — see the API editor at /apis/:id/edit
            </p>
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
