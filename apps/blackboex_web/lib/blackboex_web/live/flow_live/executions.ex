defmodule BlackboexWeb.FlowLive.Executions do
  @moduledoc """
  LiveView listing executions for a flow.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.EmptyState

  alias Blackboex.FlowExecutions
  alias Blackboex.Flows

  @impl true
  def mount(%{"id" => flow_id}, _session, socket) do
    org = socket.assigns.current_scope.organization

    case org && Flows.get_flow(org.id, flow_id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/flows")}

      flow ->
        executions = FlowExecutions.list_executions_for_flow(flow.id)

        {:ok,
         assign(socket,
           flow: flow,
           executions: executions,
           page_title: "Executions — #{flow.name}"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/flows/#{@flow.id}/edit"}
            class="text-muted-foreground hover:text-foreground"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          Executions
        </div>
        <:subtitle>{@flow.name}</:subtitle>
      </.header>

      <%= if @executions == [] do %>
        <.empty_state
          icon="hero-clock"
          title="No executions yet"
          description="Trigger this flow via its webhook to see execution history here."
        />
      <% else %>
        <div class="rounded-md border">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b bg-muted/50">
                <th class="px-4 py-2 text-left font-medium">Status</th>
                <th class="px-4 py-2 text-left font-medium">Duration</th>
                <th class="px-4 py-2 text-left font-medium">Started</th>
                <th class="px-4 py-2 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={exec <- @executions} class="border-b last:border-0">
                <td class="px-4 py-2">
                  <.badge class={exec_status_classes(exec.status)}>{exec.status}</.badge>
                </td>
                <td class="px-4 py-2 text-muted-foreground">
                  {format_duration(exec.duration_ms)}
                </td>
                <td class="px-4 py-2 text-muted-foreground">
                  {format_time(exec.inserted_at)}
                </td>
                <td class="px-4 py-2 text-right">
                  <.link
                    navigate={~p"/flows/#{@flow.id}/executions/#{exec.id}"}
                    class="text-primary hover:underline text-xs"
                  >
                    Details
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp exec_status_classes("completed"),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp exec_status_classes("failed"),
    do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp exec_status_classes("running"),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

  defp exec_status_classes(_),
    do: "bg-muted text-muted-foreground"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end
end
