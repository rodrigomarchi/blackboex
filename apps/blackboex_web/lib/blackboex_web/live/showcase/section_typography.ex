defmodule BlackboexWeb.Showcase.Sections.Typography do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Typography"
      description="Font size scale, font weights, and text color utilities."
    />
    <div class="space-y-10">
      <.showcase_block title="Scale">
        <div class="space-y-4 divide-y">
          <div
            :for={
              {class, label, sample} <- [
                {"text-2xs font-mono", "text-2xs", "The quick brown fox"},
                {"text-xs", "text-xs", "The quick brown fox jumps over the lazy dog"},
                {"text-sm", "text-sm", "The quick brown fox jumps over the lazy dog"},
                {"text-lg font-semibold", "text-lg / headings", "The quick brown fox"},
                {"text-2xl font-bold", "text-2xl / metrics", "The quick brown fox"},
                {"text-4xl font-bold", "text-4xl / public hero only", "The quick brown fox"}
              ]
            }
            class="flex items-baseline gap-4 pt-4"
          >
            <span class={["flex-1", class]}>{sample}</span>
            <span class="text-2xs text-muted-foreground font-mono w-40 shrink-0">{label}</span>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Text Color Utilities">
        <div class="space-y-3">
          <div
            :for={
              {class, desc} <- [
                {"text-foreground", "Default text -- main content"},
                {"text-muted-foreground", "Muted -- labels, secondary info"},
                {"text-destructive", "Destructive / error state"}
              ]
            }
            class="flex items-center gap-4"
          >
            <span class={["text-sm flex-1", class]}>{desc}</span>
            <span class="text-2xs font-mono text-muted-foreground w-40 shrink-0">.{class}</span>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Font Weights">
        <div class="flex gap-8 flex-wrap">
          <div
            :for={
              {class, label} <- [
                {"font-normal", "normal"},
                {"font-medium", "medium"},
                {"font-semibold", "semibold"},
                {"font-bold", "bold"},
                {"font-mono", "mono"}
              ]
            }
            class="text-center"
          >
            <p class={["text-sm", class]}>Ag</p>
            <p class="text-2xs text-muted-foreground font-mono mt-1">{label}</p>
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
