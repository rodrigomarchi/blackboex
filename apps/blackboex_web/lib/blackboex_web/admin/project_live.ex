defmodule BlackboexWeb.Admin.ProjectLive do
  @moduledoc """
  Backpex LiveResource for managing Projects in the admin panel.
  """

  alias Blackboex.Projects.Project

  use Backpex.LiveResource,
    adapter_config: [
      schema: Project,
      repo: Blackboex.Repo,
      update_changeset: &Project.admin_changeset/3,
      create_changeset: &Project.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Project"

  @impl Backpex.LiveResource
  def plural_name, do: "Projects"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      slug: %{
        module: Backpex.Fields.Text,
        label: "Slug",
        except: [:new, :edit]
      },
      description: %{
        module: Backpex.Fields.Text,
        label: "Description"
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
      }
    ]
  end
end
