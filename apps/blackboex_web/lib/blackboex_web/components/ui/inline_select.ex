defmodule BlackboexWeb.Components.UI.InlineSelect do
  @moduledoc """
  Minimal select for use outside `<.form>` contexts (property panels, inline edits).

  Options is a list of `{label, value}` tuples. The current `value` is matched
  against each tuple value to set the `selected` attribute.

  ## Examples

      <.inline_select
        options={[{"GET", "get"}, {"POST", "post"}]}
        value={@method}
        phx-change="update_method"
      />
  """
  use BlackboexWeb.Component

  attr :options, :list, required: true
  attr :value, :any, default: nil
  attr :name, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled required)

  @spec inline_select(map()) :: Phoenix.LiveView.Rendered.t()
  def inline_select(assigns) do
    ~H"""
    <select
      name={@name}
      class={
        classes([
          "w-full rounded-lg border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50",
          @class
        ])
      }
      {@rest}
    >
      <option
        :for={{label, val} <- @options}
        value={val}
        selected={to_string(val) == to_string(@value)}
      >
        {label}
      </option>
    </select>
    """
  end
end
