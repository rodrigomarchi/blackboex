defmodule BlackboexWeb.Showcase.Sections.CodeEditorField do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.CodeEditorField

  @code_readonly ~S"""
  <.code_editor_field
    id="json-display"
    value={Jason.encode!(%{status: "ok", count: 42}, pretty: true)}
    language="json"
    readonly={true}
  />
  """

  @code_editable ~S"""
  <.code_editor_field
    id="code-editor"
    value={@code}
    language="json"
    readonly={false}
    event="code_changed"
  />

  # LiveView:
  def handle_event("code_changed", %{"value" => value}, socket) do
    {:noreply, assign(socket, code: value)}
  end
  """

  @code_languages ~S"""
  <%# Elixir %>
  <.code_editor_field id="elixir-editor" value={@elixir_code} language="elixir" />

  <%# JavaScript %>
  <.code_editor_field id="js-editor" value={@js_code} language="javascript" />

  <%# JSON (default) %>
  <.code_editor_field id="json-editor" value={@json_code} language="json" />
  """

  @code_field_binding ~S"""
  <.code_editor_field
    id={"editor-#{@form[:id].value}"}
    value={@form[:schema].value}
    language="json"
    readonly={false}
    field="schema"
    event="validate"
  />

  # The field= attr causes the editor to emit changes with the field name
  # as part of the event params for form integration.
  """

  @code_height ~S"""
  <%# Fixed pixel height %>
  <.code_editor_field id="short-editor" value={@code} height="160px" />

  <%# Max height cap (default max-h-96) %>
  <.code_editor_field id="tall-editor" value={@code} max_height="max-h-48" />

  <%# Viewport-relative height %>
  <.code_editor_field id="vh-editor" value={@code} height="35vh" />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_readonly, @code_readonly)
      |> assign(:code_editable, @code_editable)
      |> assign(:code_languages, @code_languages)
      |> assign(:code_field_binding, @code_field_binding)
      |> assign(:code_height, @code_height)

    ~H"""
    <.section_header
      title="Code Editor Field"
      description="Monaco editor embed for code editing and display. Uses a LiveView hook to mount the Monaco editor. readonly=true for display, readonly=false for editing. Supports json, elixir, javascript, and other Monaco-supported languages."
      module="BlackboexWeb.Components.Shared.CodeEditorField"
    />
    <div class="space-y-10">
      <.showcase_block title="JSON Display (readonly)" code={@code_readonly}>
        <.code_editor_field
          id="showcase-json-readonly"
          value={"{\"status\": \"ok\", \"count\": 42, \"data\": [\"a\", \"b\", \"c\"]}"}
          language="json"
          readonly={true}
        />
        <p class="mt-2 text-xs text-muted-foreground">
          Default: <code class="bg-muted px-1 py-0.5 rounded">readonly=true</code>,
          <code class="bg-muted px-1 py-0.5 rounded">language="json"</code>.
          The editor requires the Monaco JS hook to render — see note below.
        </p>
      </.showcase_block>

      <.showcase_block title="Editable Field" code={@code_editable}>
        <.code_editor_field
          id="showcase-json-editable"
          value={"{\"key\": \"value\"}"}
          language="json"
          readonly={false}
          event="code_changed"
        />
      </.showcase_block>

      <.showcase_block title="Different Languages" code={@code_languages}>
        <div class="space-y-3">
          <div>
            <p class="text-xs text-muted-foreground mb-1">language="elixir"</p>
            <.code_editor_field
              id="showcase-elixir"
              value={"defmodule MyHandler do\n  def call(request) do\n    {:ok, %{status: 200, body: request.body}}\n  end\nend"}
              language="elixir"
              readonly={true}
            />
          </div>
          <div>
            <p class="text-xs text-muted-foreground mb-1">language="javascript"</p>
            <.code_editor_field
              id="showcase-js"
              value={"async function handler(req) {\n  return { status: 200, body: req.body };\n}"}
              language="javascript"
              readonly={true}
            />
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="With field Binding (Form Integration)" code={@code_field_binding}>
        <.code_editor_field
          id="showcase-field-binding"
          value={"{\"type\": \"object\"}"}
          language="json"
          readonly={false}
          field="schema"
          event="validate"
        />
        <p class="mt-2 text-xs text-muted-foreground">
          <code class="bg-muted px-1 py-0.5 rounded">field=</code> sets
          <code class="bg-muted px-1 py-0.5 rounded">data-field</code> on the hook element,
          allowing the editor to include the field name in event params for form integration.
        </p>
      </.showcase_block>

      <.showcase_block title="Height Customization" code={@code_height}>
        <div class="space-y-3">
          <div>
            <p class="text-xs text-muted-foreground mb-1">height="160px"</p>
            <.code_editor_field
              id="showcase-height-fixed"
              value={"{\n  \"example\": true\n}"}
              language="json"
              readonly={true}
              height="160px"
            />
          </div>
          <div>
            <p class="text-xs text-muted-foreground mb-1">max_height="max-h-32"</p>
            <.code_editor_field
              id="showcase-height-max"
              value={"{\n  \"example\": true\n}"}
              language="json"
              readonly={true}
              max_height="max-h-32"
            />
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Note: Monaco Hook Required">
        <.panel class="p-4 border-accent-amber/40 bg-accent-amber/5">
          <div class="flex gap-3">
            <.icon
              name="hero-information-circle"
              class="size-5 shrink-0 text-accent-amber mt-0.5"
            />
            <div class="space-y-1.5 text-sm">
              <p class="font-semibold text-foreground">CodeEditor LiveView Hook Required</p>
              <p class="text-muted-foreground">
                This component uses
                <code class="bg-muted px-1 py-0.5 rounded text-xs">phx-hook="CodeEditor"</code>.
                The hook must be registered in your
                <code class="bg-muted px-1 py-0.5 rounded text-xs">app.js</code>:
              </p>
              <pre class="text-xs bg-muted rounded p-2 mt-1">{"import CodeEditor from \"./hooks/code_editor\"\nlet liveSocket = new LiveSocket(\"/live\", Socket, {\n  hooks: { CodeEditor }\n})"}</pre>
              <p class="text-muted-foreground">
                In the showcase environment the editor container renders as a bordered box but
                Monaco will not mount without the JS hook. In production all instances render
                the full Monaco editor.
              </p>
            </div>
          </div>
        </.panel>
      </.showcase_block>
    </div>
    """
  end
end
