defmodule BlackboexWeb.Components.FlowEditor.JsonPreviewModal do
  @moduledoc """
  Modal for previewing the flow definition as formatted JSON.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.UI.SectionHeading

  attr :flow, :map, required: true
  attr :json_preview, :string, required: true

  def json_preview_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      phx-click="close_json_modal"
    >
      <div
        class="flex flex-col w-[80vw] h-[80vh] rounded-xl border bg-card shadow-2xl"
        phx-click-away="close_json_modal"
      >
        <div class="flex items-center justify-between border-b px-5 py-3">
          <.section_heading icon="hero-code-bracket" icon_class="size-5 text-accent-violet">
            Flow Definition (JSON)
          </.section_heading>
          <div class="flex items-center gap-1.5">
            <.button
              variant="outline"
              size="sm"
              phx-click={
                JS.dispatch("phx:copy_to_clipboard",
                  detail: %{text: @json_preview}
                )
              }
            >
              <.icon name="hero-clipboard-document" class="mr-1.5 size-4 text-accent-sky" /> Copy
            </.button>
            <.button
              variant="outline"
              size="sm"
              phx-click={
                JS.dispatch("phx:download_file",
                  detail: %{
                    content: @json_preview,
                    filename: "#{@flow.slug}-definition.json"
                  }
                )
              }
            >
              <.icon name="hero-arrow-down-tray" class="mr-1.5 size-4 text-accent-emerald" /> Download
            </.button>
            <.button
              variant="ghost-muted"
              size="icon-sm"
              phx-click="close_json_modal"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </.button>
          </div>
        </div>
        <div class="flex-1 overflow-auto p-5">
          <.code_editor_field
            id="code-editor-json-preview"
            value={@json_preview}
            max_height="h-full"
            class="w-full h-full rounded-lg"
          />
        </div>
      </div>
    </div>
    """
  end
end
