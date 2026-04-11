defmodule BlackboexWeb.Showcase.Sections.ConfirmDialogShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @code_warning ~S"""
  <.confirm_dialog
    title="Discard changes?"
    description="Any unsaved changes will be lost. This action cannot be undone."
    variant={:warning}
  />
  """

  @code_danger ~S"""
  <.confirm_dialog
    title="Delete API?"
    description="This will permanently delete the API and all its versions. This action cannot be undone."
    variant={:danger}
    confirm_label="Delete"
  />
  """

  @code_info ~S"""
  <.confirm_dialog
    title="Publish API?"
    description="This will make the API publicly accessible. You can unpublish it at any time."
    variant={:info}
    confirm_label="Publish"
  />
  """

  @code_custom_labels ~S"""
  <.confirm_dialog
    title="Delete this item?"
    description="This action is irreversible."
    variant={:danger}
    confirm_label="Yes, delete"
    cancel_label="Keep it"
  />
  """

  @code_usage_pattern ~S"""
  # 1. In mount/2, initialize the assign:
  {:ok, assign(socket, confirm: nil)}

  # 2. To trigger the dialog, set the confirm assign:
  assign(socket, confirm: %{
    title: "Delete flow?",
    description: "This action cannot be undone.",
    variant: :danger,
    confirm_label: "Delete",
    event: "delete",
    meta: %{"id" => flow_id}
  })

  # 3. In your template:
  <.confirm_dialog
    :if={@confirm}
    title={@confirm.title}
    description={@confirm.description}
    variant={@confirm[:variant] || :warning}
    confirm_label={@confirm[:confirm_label] || "Confirm"}
  />

  # 4. Handle the emitted events in your LiveView:
  def handle_event("execute_confirm", _params, socket) do
    %{event: event, meta: meta} = socket.assigns.confirm
    handle_event(event, meta, assign(socket, confirm: nil))
  end

  def handle_event("dismiss_confirm", _params, socket) do
    {:noreply, assign(socket, confirm: nil)}
  end
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_warning, @code_warning)
      |> assign(:code_danger, @code_danger)
      |> assign(:code_info, @code_info)
      |> assign(:code_custom_labels, @code_custom_labels)
      |> assign(:code_usage_pattern, @code_usage_pattern)

    ~H"""
    <.section_header
      title="ConfirmDialog"
      description="Confirmation dialog for destructive or important actions. Renders inline as a confirmation overlay with three severity variants. Triggered by setting a @confirm assign in the LiveView."
      module="BlackboexWeb.Components.ConfirmDialog"
    />
    <div class="space-y-10">
      <.showcase_block title="Warning variant (default)" code={@code_warning}>
        <div class="relative rounded-xl border bg-black/30 min-h-[220px] flex items-center justify-center overflow-hidden">
          <div class="relative z-10 w-full max-w-md mx-4 rounded-xl border bg-card text-card-foreground shadow-2xl">
            <div class="p-6">
              <div class="flex items-start gap-4">
                <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-yellow-500/15">
                  <.icon name="hero-exclamation-circle" class="size-5 text-yellow-600" />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-base font-semibold text-foreground">Discard changes?</h3>
                  <p class="mt-1.5 text-sm text-muted-foreground leading-relaxed">
                    Any unsaved changes will be lost. This action cannot be undone.
                  </p>
                </div>
              </div>
            </div>
            <div class="flex items-center justify-end gap-2 border-t bg-muted/30 px-6 py-3 rounded-b-xl">
              <.button variant="outline" size="sm" class="min-w-[5rem]">Cancel</.button>
              <.button variant="default" size="sm" class="min-w-[5rem]">
                <.icon name="hero-check-mini" class="mr-1.5 size-3.5" /> Confirm
              </.button>
            </div>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Danger variant" code={@code_danger}>
        <div class="relative rounded-xl border bg-black/30 min-h-[220px] flex items-center justify-center overflow-hidden">
          <div class="relative z-10 w-full max-w-md mx-4 rounded-xl border bg-card text-card-foreground shadow-2xl">
            <div class="p-6">
              <div class="flex items-start gap-4">
                <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-destructive/15">
                  <.icon name="hero-exclamation-triangle" class="size-5 text-destructive" />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-base font-semibold text-foreground">Delete API?</h3>
                  <p class="mt-1.5 text-sm text-muted-foreground leading-relaxed">
                    This will permanently delete the API and all its versions. This action cannot be undone.
                  </p>
                </div>
              </div>
            </div>
            <div class="flex items-center justify-end gap-2 border-t bg-muted/30 px-6 py-3 rounded-b-xl">
              <.button variant="outline" size="sm" class="min-w-[5rem]">Cancel</.button>
              <.button variant="destructive" size="sm" class="min-w-[5rem]">
                <.icon name="hero-trash-mini" class="mr-1.5 size-3.5" /> Delete
              </.button>
            </div>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Info variant" code={@code_info}>
        <div class="relative rounded-xl border bg-black/30 min-h-[220px] flex items-center justify-center overflow-hidden">
          <div class="relative z-10 w-full max-w-md mx-4 rounded-xl border bg-card text-card-foreground shadow-2xl">
            <div class="p-6">
              <div class="flex items-start gap-4">
                <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-blue-500/15">
                  <.icon name="hero-information-circle" class="size-5 text-blue-600" />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-base font-semibold text-foreground">Publish API?</h3>
                  <p class="mt-1.5 text-sm text-muted-foreground leading-relaxed">
                    This will make the API publicly accessible. You can unpublish it at any time.
                  </p>
                </div>
              </div>
            </div>
            <div class="flex items-center justify-end gap-2 border-t bg-muted/30 px-6 py-3 rounded-b-xl">
              <.button variant="outline" size="sm" class="min-w-[5rem]">Cancel</.button>
              <.button variant="default" size="sm" class="min-w-[5rem]">
                <.icon name="hero-check-mini" class="mr-1.5 size-3.5" /> Publish
              </.button>
            </div>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Custom labels" code={@code_custom_labels}>
        <div class="relative rounded-xl border bg-black/30 min-h-[220px] flex items-center justify-center overflow-hidden">
          <div class="relative z-10 w-full max-w-md mx-4 rounded-xl border bg-card text-card-foreground shadow-2xl">
            <div class="p-6">
              <div class="flex items-start gap-4">
                <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-destructive/15">
                  <.icon name="hero-exclamation-triangle" class="size-5 text-destructive" />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-base font-semibold text-foreground">Delete this item?</h3>
                  <p class="mt-1.5 text-sm text-muted-foreground leading-relaxed">
                    This action is irreversible.
                  </p>
                </div>
              </div>
            </div>
            <div class="flex items-center justify-end gap-2 border-t bg-muted/30 px-6 py-3 rounded-b-xl">
              <.button variant="outline" size="sm" class="min-w-[5rem]">Keep it</.button>
              <.button variant="destructive" size="sm" class="min-w-[5rem]">
                <.icon name="hero-trash-mini" class="mr-1.5 size-3.5" /> Yes, delete
              </.button>
            </div>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Usage pattern (code only)" code={@code_usage_pattern}>
        <p class="text-sm text-muted-foreground">
          The dialog is controlled via the <code class="font-mono text-xs bg-muted px-1 rounded">@confirm</code>
          assign. See the code example above for the full LiveView integration pattern.
        </p>
      </.showcase_block>
    </div>
    """
  end
end
