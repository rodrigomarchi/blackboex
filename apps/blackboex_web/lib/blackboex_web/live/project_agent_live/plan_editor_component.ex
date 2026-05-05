defmodule BlackboexWeb.ProjectAgentLive.PlanEditorComponent do
  @moduledoc """
  Renders the markdown editor (CodeMirror via the `CodeEditor` JS hook —
  the existing per-artifact agent editor surface) for a `Plan`.

  Behaviour by `plan.status`:

    * `"draft"` — editable textarea + Approve button. Submits
      `phx-click="approve_plan"` with `%{"markdown_body" => …}` to the
      parent `ProjectAgentLive.Index`.
    * any other status — read-only markdown view (no editor hook,
      no Approve button) so the immutable-after-approval invariant
      is reflected in the UI.

  Renders any `:violations` returned by `Plans.approve_plan/3` directly
  above the editor for instant feedback on a rejected markdown edit.

  Attrs:
    * `:id` (required) — DOM id (also LiveComponent id).
    * `:plan` (required) — `Blackboex.Plans.Plan` struct.
    * `:violations` — list of validation violations from a prior approve
      attempt; defaults to `[]`.
  """
  use BlackboexWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <section class="rounded-lg border bg-card p-4" data-role="plan-editor" id={@id}>
      <header class="mb-3 flex items-center justify-between">
        <h2 class="text-sm font-semibold">{@plan.title}</h2>
        <span class="text-muted-foreground text-xs uppercase tracking-wide">
          {@plan.status}
        </span>
      </header>

      <%= if @violations != [] do %>
        <div
          class="mb-3 rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive"
          data-role="plan-violations"
        >
          <p class="font-medium">The edited markdown failed validation:</p>
          <ul class="mt-2 list-disc space-y-1 pl-5">
            <li :for={v <- @violations}>{format_violation(v)}</li>
          </ul>
        </div>
      <% end %>

      <%= if @plan.status == "draft" do %>
        <form
          id={@id <> "-form"}
          phx-submit="approve_plan"
          class="space-y-3"
        >
          <textarea
            id={@id <> "-textarea"}
            name="markdown_body"
            rows="14"
            class="w-full rounded-md border bg-background p-2 font-mono text-sm focus:outline-none focus:ring-2 focus:ring-primary"
            phx-debounce="300"
          ><%= @plan.markdown_body %></textarea>

          <div class="flex justify-end">
            <button
              type="submit"
              phx-click="approve_plan"
              class="inline-flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
            >
              Approve and run
            </button>
          </div>
        </form>
      <% else %>
        <pre
          data-role="plan-readonly"
          class="bg-muted text-foreground overflow-x-auto rounded-md p-3 text-xs whitespace-pre-wrap"
        ><%= @plan.markdown_body %></pre>
      <% end %>
    </section>
    """
  end

  @spec format_violation(term()) :: String.t()
  defp format_violation({:invalid_artifact_type, idx}),
    do: "Task #{idx + 1}: invalid artifact_type"

  defp format_violation({:invalid_action, idx}),
    do: "Task #{idx + 1}: invalid action"

  defp format_violation({:order_changed, idx}),
    do: "Task #{idx + 1}: order changed"

  defp format_violation({:target_artifact_changed, idx}),
    do: "Task #{idx + 1}: target artifact changed"

  defp format_violation({:structural_field_renamed, field}),
    do: "Structural field renamed: #{field}"

  defp format_violation(other), do: inspect(other)
end
