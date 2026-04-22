defmodule BlackboexWeb.Components.FlowEditor.FlowChatDrawer do
  @moduledoc """
  Right-side drawer that wraps the `FlowChatPanel` inside the Flow editor.

  Rendered only when `@show` is true. Close button dispatches
  `phx-click="toggle_chat"` so the parent LiveView flips the visibility
  assign with the same event that opens it.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Editor.FlowChatPanel

  attr :show, :boolean, default: false
  attr :messages, :list, default: []
  attr :input, :string, default: ""
  attr :loading, :boolean, default: false
  attr :current_stream, :string, default: nil

  def flow_chat_drawer(%{show: false} = assigns) do
    ~H"""
    """
  end

  def flow_chat_drawer(assigns) do
    ~H"""
    <aside class="flex w-[26rem] shrink-0 flex-col border-l bg-card animate-in slide-in-from-right duration-200">
      <.flow_chat_panel
        messages={@messages}
        input={@input}
        loading={@loading}
        current_stream={@current_stream}
      />
    </aside>
    """
  end
end
