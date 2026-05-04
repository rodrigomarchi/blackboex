defmodule BlackboexWeb.Components.OrgProjectSwitcher do
  @moduledoc """
  Shows the current organization context in the sidebar with a dropdown
  for switching between organizations.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.DropdownMenu

  alias Blackboex.Organizations

  attr :current_scope, :map, required: true
  attr :orgs, :list, default: nil

  def org_project_switcher(assigns) do
    user = assigns.current_scope && assigns.current_scope.user
    org = assigns.current_scope && assigns.current_scope.organization

    orgs = assigns.orgs || if(user, do: Organizations.list_user_organizations(user), else: [])

    assigns =
      assigns
      |> assign(:orgs, orgs)
      |> assign(:current_org, org)

    ~H"""
    <div class="space-y-1.5">
      <%!-- Organization row --%>
      <div class="flex items-center gap-2">
        <div class="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-primary/10 text-primary text-2xs font-bold">
          {org_initials(@current_org)}
        </div>
        <div class="flex-1 min-w-0 flex items-center gap-1">
          <.dropdown_menu>
            <.dropdown_menu_trigger>
              <button class="flex min-w-0 items-center gap-1 text-left group">
                <span class="text-xs font-medium text-muted-foreground truncate group-hover:text-foreground transition-colors">
                  {org_name(@current_org)}
                </span>
                <.icon
                  name="hero-chevron-down-micro"
                  class="size-3 text-muted-foreground/50 shrink-0 group-hover:text-foreground transition-colors"
                />
              </button>
            </.dropdown_menu_trigger>
            <.dropdown_menu_content class="w-56 ml-0 left-0 top-full mt-1 rounded-lg border bg-popover p-1 shadow-lg">
              <div class="px-2 py-1.5 text-2xs font-semibold uppercase tracking-wider text-muted-foreground">
                Switch organization
              </div>
              <.link
                :for={org <- @orgs}
                navigate={"/orgs/#{org.slug}"}
                class={[
                  "flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm hover:bg-accent cursor-pointer",
                  if(org.id == (@current_org && @current_org.id), do: "bg-accent/50", else: "")
                ]}
              >
                <div class="flex h-5 w-5 shrink-0 items-center justify-center rounded bg-muted text-2xs font-medium">
                  {org_initials(org)}
                </div>
                <span class="truncate">{org.name}</span>
                <.icon
                  :if={org.id == (@current_org && @current_org.id)}
                  name="hero-check-micro"
                  class="ml-auto size-3.5 text-primary"
                />
              </.link>
            </.dropdown_menu_content>
          </.dropdown_menu>
          <div :if={@current_org} class="ml-auto flex items-center gap-0.5">
            <.link
              navigate={"/orgs/#{@current_org.slug}/settings"}
              class="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
              title="Org settings"
              aria-label="Org settings"
            >
              <.icon name="hero-cog-6-tooth-micro" class="size-3.5" />
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp org_initials(nil), do: "?"

  defp org_initials(%{name: name}) when is_binary(name) do
    name
    |> String.split(~r/\s+/)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp org_name(nil), do: "Select org"
  defp org_name(%{name: name}), do: name
end
