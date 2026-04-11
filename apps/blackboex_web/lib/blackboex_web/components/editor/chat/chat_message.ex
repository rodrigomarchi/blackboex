defmodule BlackboexWeb.Components.Editor.Chat.ChatMessage do
  @moduledoc """
  Function components for rendering individual chat messages in the agent timeline.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Editor.ChatPanelHelpers,
    only: [format_timestamp: 1]

  import BlackboexWeb.Components.Editor.CodeLabel

  @doc "Renders a single user or agent message step in the timeline."
  attr :event, :map, required: true

  def render_message_step(assigns) do
    ~H"""
    <div class="relative pb-3 pt-1">
      <%!-- Timeline node on the border-l line --%>
      <div class={[
        "absolute -left-[7px] top-3 size-[9px] rounded-full border-2 bg-background",
        if(@event.role == "user", do: "border-primary", else: "border-muted-foreground/50")
      ]} />

      <div class={[
        "rounded-md px-3 py-2 text-sm ml-2",
        if(@event.role == "user",
          do: "bg-primary/10 border border-primary/20",
          else: "bg-muted/50"
        )
      ]}>
        <div class="flex items-center gap-1.5 mb-1">
          <.icon
            name={if(@event.role == "user", do: "hero-user", else: "hero-sparkles")}
            class={
              if(@event.role == "user",
                do: "size-3 text-accent-blue",
                else: "size-3 text-accent-violet"
              )
            }
          />
          <.code_label variant="dark">
            {if @event.role == "user", do: "You", else: "Agent"}
          </.code_label>
          <span class="flex-1" />
          <span class="text-2xs text-muted-foreground">
            {format_timestamp(@event[:timestamp])}
          </span>
        </div>
        <p class="whitespace-pre-wrap text-xs leading-relaxed">{@event.content || ""}</p>
      </div>
    </div>
    """
  end
end
