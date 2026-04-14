defmodule BlackboexWeb.Components.Shared.Breadcrumbs do
  @moduledoc """
  Breadcrumb navigation showing the Org > Project > Section hierarchy.
  """
  use BlackboexWeb.Component
  import BlackboexWeb.Components.Icon

  attr :items, :list, required: true
  # Each item is %{label: "...", href: "..."} or %{label: "..."} for current

  def breadcrumbs(assigns) do
    ~H"""
    <nav class="flex items-center gap-1.5 text-sm text-muted-foreground" aria-label="Breadcrumb">
      <.link
        :for={{item, idx} <- Enum.with_index(@items)}
        navigate={item[:href]}
        class={[
          "flex items-center gap-1.5",
          if(is_nil(item[:href]),
            do: "text-foreground font-medium",
            else: "hover:text-foreground transition-colors"
          )
        ]}
      >
        <.icon :if={idx > 0} name="hero-chevron-right" class="size-3.5 shrink-0" />
        {item.label}
      </.link>
    </nav>
    """
  end
end
