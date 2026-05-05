defmodule BlackboexWeb.ProjectAgentLive.TaskRowComponent do
  @moduledoc """
  One row in the streamed task list of `ProjectAgentLive.Index`.

  Renders the task title, artifact type, action, status (with a colored
  status dot), and the error message when `task.status == "failed"`.

  Attrs:
    * `:id` (required) — DOM id (also LiveComponent id).
    * `:task` (required) — `Blackboex.Plans.PlanTask` struct.
  """
  use BlackboexWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <article
      id={@id}
      class="flex items-start gap-3 rounded-md border bg-card p-3"
      data-role="task-row"
      data-status={@task.status}
    >
      <span class={["mt-1.5 inline-block h-2.5 w-2.5 rounded-full", status_dot_class(@task.status)]} />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium">{@task.title}</p>
        <p class="text-muted-foreground text-xs">
          {@task.artifact_type} · {@task.action} · <span data-role="task-status">{@task.status}</span>
        </p>
        <%= if @task.status == "failed" and @task.error_message not in [nil, ""] do %>
          <p class="text-destructive mt-1 text-xs" data-role="task-error">
            {@task.error_message}
          </p>
        <% end %>
      </div>
    </article>
    """
  end

  @spec status_dot_class(String.t()) :: String.t()
  defp status_dot_class("pending"), do: "bg-muted-foreground/40"
  defp status_dot_class("running"), do: "bg-primary animate-pulse"
  defp status_dot_class("done"), do: "bg-emerald-500"
  defp status_dot_class("failed"), do: "bg-destructive"
  defp status_dot_class("skipped"), do: "bg-muted-foreground/20"
  defp status_dot_class(_), do: "bg-muted-foreground/40"
end
