defmodule BlackboexWeb.Admin.ProjectMembershipLive do
  @moduledoc """
  Backpex LiveResource for managing ProjectMemberships in the admin panel.
  """

  alias Blackboex.Projects.ProjectMembership

  use Backpex.LiveResource,
    adapter_config: [
      schema: ProjectMembership,
      repo: Blackboex.Repo,
      update_changeset: &ProjectMembership.admin_changeset/3,
      create_changeset: &ProjectMembership.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Project Membership"

  @impl Backpex.LiveResource
  def plural_name, do: "Project Memberships"

  @impl Backpex.LiveResource
  def fields do
    [
      project_id: %{
        module: Backpex.Fields.Text,
        label: "Project ID"
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID"
      },
      role: %{
        module: Backpex.Fields.Select,
        label: "Role",
        options: [Admin: "admin", Editor: "editor", Viewer: "viewer"]
      }
    ]
  end
end
