defmodule BlackboexWeb.Components.PipelineStatus do
  @moduledoc """
  Inline pipeline progress component for the chat panel.
  Shows step-by-step progress with checkmarks, spinners, and pending indicators.
  """

  use BlackboexWeb, :html

  @steps_order [
    :generating_code,
    :formatting,
    :compiling,
    :linting,
    :generating_tests,
    :running_tests,
    :generating_docs
  ]

  @step_labels %{
    generating_code: "Generating code",
    formatting: "Formatting",
    compiling: "Compiling",
    linting: "Running linters",
    generating_tests: "Generating tests",
    running_tests: "Running tests",
    generating_docs: "Generating docs",
    fixing_code: "Fixing code",
    fixing_tests: "Fixing tests",
    done: "Done",
    failed: "Failed"
  }

  attr :status, :atom, required: true
  attr :show_cancel, :boolean, default: true

  @spec pipeline_progress_steps(map()) :: Phoenix.LiveView.Rendered.t()
  def pipeline_progress_steps(assigns) do
    assigns = assign(assigns, :steps, build_steps(assigns.status))

    ~H"""
    <div class="space-y-1">
      <div :for={{step, state} <- @steps} class="flex items-center gap-2 text-xs">
        <span :if={state == :done} class="text-green-600 font-medium">✓</span>
        <span :if={state == :active}>
          <.icon name="hero-arrow-path" class="size-3 animate-spin text-primary" />
        </span>
        <span :if={state == :pending} class="text-muted-foreground">○</span>
        <span class={[
          if(state == :active, do: "text-foreground font-medium", else: "text-muted-foreground")
        ]}>
          {step_label(step)}
        </span>
      </div>
      <button
        :if={@show_cancel}
        phx-click="cancel_pipeline"
        class="text-xs text-muted-foreground hover:text-foreground mt-1"
      >
        Cancel
      </button>
    </div>
    """
  end

  defp build_steps(current_status) do
    # Find where we are in the pipeline
    current_idx =
      Enum.find_index(@steps_order, &(&1 == current_status))

    # Handle fix steps by mapping to the appropriate position
    current_idx =
      cond do
        current_idx != nil -> current_idx
        current_status in [:fixing_code, :fixing_tests] -> length(@steps_order)
        current_status == :done -> length(@steps_order)
        true -> 0
      end

    @steps_order
    |> Enum.with_index()
    |> Enum.map(fn {step, idx} ->
      state =
        cond do
          idx < current_idx -> :done
          idx == current_idx -> :active
          true -> :pending
        end

      {step, state}
    end)
  end

  defp step_label(step), do: Map.get(@step_labels, step, to_string(step))
end
