defmodule BlackboexWeb.Components.FlowEditor.JsonPreviewModal do
  @moduledoc """
  Modal for previewing the flow definition as formatted JSON.
  """

  use BlackboexWeb, :html

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
          <div class="flex items-center gap-2">
            <.icon name="hero-code-bracket" class="size-5 text-violet-400" />
            <h2 class="text-sm font-semibold">Flow Definition (JSON)</h2>
          </div>
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
              <.icon name="hero-clipboard-document" class="mr-1.5 size-4 text-sky-400" /> Copy
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
              <.icon name="hero-arrow-down-tray" class="mr-1.5 size-4 text-emerald-400" /> Download
            </.button>
            <button
              phx-click="close_json_modal"
              class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
        </div>
        <div class="flex-1 overflow-auto p-5">
          <div
            id="code-editor-json-preview"
            phx-hook="CodeEditor"
            data-language="json"
            data-readonly="true"
            data-value={@json_preview}
            class="w-full h-full rounded-lg overflow-hidden"
          />
        </div>
      </div>
    </div>
    """
  end
end
