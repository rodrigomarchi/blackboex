defmodule BlackboexWeb.Showcase.Sections.Tokens do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Design Tokens"
      description="Color palette, semantic tokens, accent colors, status colors, and border radius scale."
    />
    <div class="space-y-10">
      <.showcase_block title="Base Palette">
        <div class="grid grid-cols-4 gap-3">
          <div
            :for={
              {name, class, fg} <- [
                {"background", "bg-background", "text-foreground"},
                {"foreground", "bg-foreground", "text-background"},
                {"card", "bg-card", "text-card-foreground"},
                {"muted", "bg-muted", "text-muted-foreground"},
                {"primary", "bg-primary", "text-primary-foreground"},
                {"secondary", "bg-secondary", "text-secondary-foreground"},
                {"accent", "bg-accent", "text-accent-foreground"},
                {"destructive", "bg-destructive", "text-destructive-foreground"}
              ]
            }
            class="space-y-1"
          >
            <div class={[
              "rounded-lg border h-14 flex items-center justify-center text-xs font-medium",
              class,
              fg
            ]}>
              {name}
            </div>
            <p class="text-2xs text-muted-foreground font-mono text-center">--{name}</p>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Semantic">
        <div class="grid grid-cols-4 gap-3">
          <div
            :for={
              {name, class, fg} <- [
                {"success", "bg-success", "text-success-foreground"},
                {"warning", "bg-warning", "text-warning-foreground"},
                {"info", "bg-info", "text-info-foreground"},
                {"border", "bg-border", "text-foreground"}
              ]
            }
            class="space-y-1"
          >
            <div class={[
              "rounded-lg border h-14 flex items-center justify-center text-xs font-medium",
              class,
              fg
            ]}>
              {name}
            </div>
            <p class="text-2xs text-muted-foreground font-mono text-center">--{name}</p>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Accent Colors">
        <div class="grid grid-cols-6 gap-3">
          <div
            :for={
              {name, class} <- [
                {"blue", "bg-accent-blue"},
                {"violet", "bg-accent-violet"},
                {"amber", "bg-accent-amber"},
                {"emerald", "bg-accent-emerald"},
                {"red", "bg-accent-red"},
                {"purple", "bg-accent-purple"},
                {"sky", "bg-accent-sky"},
                {"teal", "bg-accent-teal"},
                {"rose", "bg-accent-rose"},
                {"orange", "bg-accent-orange"},
                {"cyan", "bg-accent-cyan"}
              ]
            }
            class="space-y-1"
          >
            <div class={["rounded-lg h-10", class]} />
            <p class="text-2xs text-muted-foreground font-mono text-center">{name}</p>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Status -- API Lifecycle">
        <div class="grid grid-cols-4 gap-3">
          <div
            :for={
              {name, class, fg} <- [
                {"draft", "bg-[var(--status-draft)]", "text-[var(--status-draft-foreground)]"},
                {"compiled", "bg-[var(--status-compiled)]",
                 "text-[var(--status-compiled-foreground)]"},
                {"published", "bg-[var(--status-published)]",
                 "text-[var(--status-published-foreground)]"},
                {"archived", "bg-[var(--status-archived)]",
                 "text-[var(--status-archived-foreground)]"}
              ]
            }
            class="space-y-1"
          >
            <div class={[
              "rounded-lg border h-14 flex items-center justify-center text-xs font-medium",
              class,
              fg
            ]}>
              {name}
            </div>
            <p class="text-2xs text-muted-foreground font-mono text-center">--status-{name}</p>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Border Radius">
        <div class="flex gap-6 items-end">
          <div
            :for={
              {_name, class} <- [
                {"sm", "rounded-sm"},
                {"default", "rounded"},
                {"md", "rounded-md"},
                {"lg", "rounded-lg"},
                {"xl", "rounded-xl"},
                {"2xl", "rounded-2xl"},
                {"full", "rounded-full"}
              ]
            }
            class="space-y-2 text-center"
          >
            <div class={["w-16 h-16 bg-accent border", class]} />
            <p class="text-2xs text-muted-foreground font-mono">{class}</p>
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
