defmodule BlackboexWeb.Admin.UserTokenLive do
  @moduledoc """
  Backpex LiveResource for viewing user tokens in the admin panel.
  Read-only. Token values are hidden for security.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Accounts.UserToken,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Accounts.UserToken.admin_changeset/3,
      create_changeset: &Blackboex.Accounts.UserToken.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "User Token"

  @impl Backpex.LiveResource
  def plural_name, do: "User Tokens"

  @impl Backpex.LiveResource
  def fields do
    [
      context: %{
        module: Backpex.Fields.Text,
        label: "Context",
        searchable: true
      },
      sent_to: %{
        module: Backpex.Fields.Text,
        label: "Sent To",
        searchable: true
      },
      token: %{
        module: Backpex.Fields.Text,
        label: "Token",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          ~H"""
          <span class="text-xs text-muted-foreground italic">[binary token — hidden for security]</span>
          """
        end
      },
      authenticated_at: %{
        module: Backpex.Fields.DateTime,
        label: "Authenticated At"
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created"
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, _action, _item), do: platform_admin?(assigns)

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
