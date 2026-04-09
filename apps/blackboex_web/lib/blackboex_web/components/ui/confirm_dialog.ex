defmodule BlackboexWeb.Components.ConfirmDialog do
  @moduledoc """
  Rich confirmation dialog component that replaces native browser `confirm()`.

  ## Usage

  Add to your LiveView assigns:

      assign(socket, confirm: nil)

  Show the dialog by setting `confirm` to a map:

      assign(socket, confirm: %{
        title: "Delete flow?",
        description: "This action cannot be undone.",
        variant: :danger,
        confirm_label: "Delete",
        event: "delete",
        meta: %{"id" => flow_id}
      })

  In your template:

      <.confirm_dialog
        :if={@confirm}
        title={@confirm.title}
        description={@confirm.description}
        variant={@confirm[:variant] || :warning}
        confirm_label={@confirm[:confirm_label] || "Confirm"}
      />

  The component emits `"execute_confirm"` when confirmed and `"dismiss_confirm"` when cancelled.
  Handle them in your LiveView:

      def handle_event("execute_confirm", _params, socket) do
        %{event: event, meta: meta} = socket.assigns.confirm
        # Dispatch to the original handler
        handle_event(event, meta, assign(socket, confirm: nil))
      end

      def handle_event("dismiss_confirm", _params, socket) do
        {:noreply, assign(socket, confirm: nil)}
      end
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon
  import BlackboexWeb.Components.Button

  @type variant :: :danger | :warning | :info

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :variant, :atom, default: :warning, values: [:danger, :warning, :info]
  attr :confirm_label, :string, default: "Confirm"
  attr :cancel_label, :string, default: "Cancel"

  @spec confirm_dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def confirm_dialog(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center"
      phx-window-keydown="dismiss_confirm"
      phx-key="Escape"
    >
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/60 backdrop-blur-sm animate-in fade-in duration-150"
        phx-click="dismiss_confirm"
      />

      <%!-- Dialog --%>
      <div class="relative z-10 w-full max-w-md mx-4 rounded-xl border bg-card text-card-foreground shadow-2xl animate-in zoom-in-95 fade-in duration-200">
        <div class="p-6">
          <%!-- Icon + Title --%>
          <div class="flex items-start gap-4">
            <div class={[
              "flex size-10 shrink-0 items-center justify-center rounded-full",
              variant_icon_bg(@variant)
            ]}>
              <.icon name={variant_icon(@variant)} class={"size-5 #{variant_icon_color(@variant)}"} />
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="text-base font-semibold text-foreground">{@title}</h3>
              <p class="mt-1.5 text-sm text-muted-foreground leading-relaxed">{@description}</p>
            </div>
          </div>
        </div>

        <%!-- Actions --%>
        <div class="flex items-center justify-end gap-2 border-t bg-muted/30 px-6 py-3 rounded-b-xl">
          <.button
            variant="outline"
            size="sm"
            phx-click="dismiss_confirm"
            class="min-w-[5rem]"
          >
            {@cancel_label}
          </.button>
          <.button
            variant={variant_button(@variant)}
            size="sm"
            phx-click="execute_confirm"
            class="min-w-[5rem]"
          >
            <.icon name={variant_confirm_icon(@variant)} class="mr-1.5 size-3.5" />
            {@confirm_label}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  @spec variant_icon(variant()) :: String.t()
  defp variant_icon(:danger), do: "hero-exclamation-triangle"
  defp variant_icon(:warning), do: "hero-exclamation-circle"
  defp variant_icon(:info), do: "hero-information-circle"

  @spec variant_icon_bg(variant()) :: String.t()
  defp variant_icon_bg(:danger), do: "bg-red-500/15"
  defp variant_icon_bg(:warning), do: "bg-amber-500/15"
  defp variant_icon_bg(:info), do: "bg-blue-500/15"

  @spec variant_icon_color(variant()) :: String.t()
  defp variant_icon_color(:danger), do: "text-red-500"
  defp variant_icon_color(:warning), do: "text-amber-500"
  defp variant_icon_color(:info), do: "text-blue-500"

  @spec variant_button(variant()) :: String.t()
  defp variant_button(:danger), do: "destructive"
  defp variant_button(:warning), do: "default"
  defp variant_button(:info), do: "default"

  @spec variant_confirm_icon(variant()) :: String.t()
  defp variant_confirm_icon(:danger), do: "hero-trash-mini"
  defp variant_confirm_icon(:warning), do: "hero-check-mini"
  defp variant_confirm_icon(:info), do: "hero-check-mini"
end
