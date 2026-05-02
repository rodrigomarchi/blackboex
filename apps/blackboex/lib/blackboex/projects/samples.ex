defmodule Blackboex.Projects.Samples do
  @moduledoc """
  Provisioning and synchronization for managed sample workspaces.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis
  alias Blackboex.Apis.{Api, Files}
  alias Blackboex.Flows
  alias Blackboex.Flows.Flow
  alias Blackboex.Pages
  alias Blackboex.Pages.Page
  alias Blackboex.Playgrounds
  alias Blackboex.Playgrounds.Playground
  alias Blackboex.Projects.{Project, ProjectMembership}
  alias Blackboex.Repo
  alias Blackboex.Samples.Manifest

  @sample_project_name "Exemplos"

  @type sync_result :: %{
          project: Project.t(),
          apis: non_neg_integer(),
          flows: non_neg_integer(),
          pages: non_neg_integer(),
          playgrounds: non_neg_integer()
        }

  @spec provision_for_org(
          Blackboex.Organizations.Organization.t(),
          Blackboex.Accounts.User.t()
        ) ::
          {:ok, %{project: Project.t(), membership: ProjectMembership.t()}}
          | {:error, term()}
  def provision_for_org(org, user) do
    Repo.transaction(fn ->
      project = insert_sample_project!(org)
      membership = insert_project_membership!(project, user)
      sync_project!(project, user)
      %{project: project, membership: membership}
    end)
  end

  @spec sync_sample_workspace(Project.t(), Blackboex.Accounts.User.t() | nil) ::
          {:ok, sync_result()} | {:error, term()}
  def sync_sample_workspace(project, user \\ nil)

  def sync_sample_workspace(%Project{sample_workspace: true} = project, user) do
    Repo.transaction(fn -> sync_project!(project, user) end)
  end

  def sync_sample_workspace(%Project{} = project, _user) do
    {:error, {:not_sample_workspace, project.id}}
  end

  @spec sync_all_sample_workspaces(keyword()) ::
          {:ok, [sync_result()]} | {:error, term()}
  def sync_all_sample_workspaces(opts \\ []) do
    Repo.transaction(fn ->
      opts
      |> sample_workspace_query()
      |> Repo.all()
      |> Enum.map(&sync_project!(&1, nil))
    end)
  end

  @spec dry_run(keyword()) :: %{
          projects: non_neg_integer(),
          apis: non_neg_integer(),
          flows: non_neg_integer(),
          pages: non_neg_integer(),
          playgrounds: non_neg_integer()
        }
  def dry_run(opts \\ []) do
    projects = opts |> sample_workspace_query() |> Repo.aggregate(:count)

    %{
      projects: projects,
      apis: projects * length(Manifest.list_by_kind(:api)),
      flows: projects * length(Manifest.list_by_kind(:flow)),
      pages: projects * length(Manifest.list_by_kind(:page)),
      playgrounds: projects * length(Manifest.list_by_kind(:playground))
    }
  end

  defp sample_workspace_query(opts) do
    base = from p in Project, where: p.sample_workspace == true

    base
    |> maybe_filter(:organization_id, opts[:org_id])
    |> maybe_filter(:id, opts[:project_id])
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    where(query, [p], field(p, ^field) == ^value)
  end

  defp insert_sample_project!(org) do
    %Project{}
    |> Project.changeset(%{
      name: @sample_project_name,
      description: "Projeto inicial com exemplos oficiais do Blackboex.",
      organization_id: org.id,
      sample_workspace: true,
      sample_manifest_version: Manifest.version(),
      sample_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp insert_project_membership!(project, user) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{
      project_id: project.id,
      user_id: user.id,
      role: :admin
    })
    |> Repo.insert!()
  end

  defp sync_project!(project, user) do
    user = user || sample_actor(project)
    purge_obsolete_samples!(project)

    flow_by_uuid = upsert_flows!(project, user)

    result = %{
      project: mark_synced!(project),
      apis: upsert_apis!(project, user),
      flows: map_size(flow_by_uuid),
      pages: upsert_pages!(project, user),
      playgrounds: upsert_playgrounds!(project, user, flow_by_uuid)
    }

    result
  end

  defp sample_actor(project) do
    from(pm in ProjectMembership,
      where: pm.project_id == ^project.id,
      order_by: [asc: pm.inserted_at],
      preload: [:user],
      limit: 1
    )
    |> Repo.one()
    |> case do
      %{user: user} -> user
      nil -> nil
    end
  end

  defp mark_synced!(project) do
    project
    |> Project.update_changeset(%{
      sample_workspace: true,
      sample_manifest_version: Manifest.version(),
      sample_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update!()
  end

  defp purge_obsolete_samples!(project) do
    purge_obsolete!(Api, project.id, Manifest.list_by_kind(:api))
    purge_obsolete!(Flow, project.id, Manifest.list_by_kind(:flow))
    purge_obsolete!(Page, project.id, Manifest.list_by_kind(:page))
    purge_obsolete!(Playground, project.id, Manifest.list_by_kind(:playground))
  end

  defp purge_obsolete!(schema, project_id, samples) do
    current = Enum.map(samples, & &1.sample_uuid)

    from(r in schema,
      where: r.project_id == ^project_id,
      where: not is_nil(r.sample_uuid),
      where: r.sample_uuid not in ^current
    )
    |> Repo.delete_all()
  end

  defp upsert_apis!(project, user) do
    Manifest.list_by_kind(:api)
    |> Enum.each(&upsert_api!(project, user, &1))
    |> then(fn _ -> length(Manifest.list_by_kind(:api)) end)
  end

  defp upsert_api!(project, user, sample) do
    attrs = %{
      name: sample.name,
      description: sample.description,
      organization_id: project.organization_id,
      project_id: project.id,
      user_id: user && user.id,
      template_id: sample.id,
      sample_uuid: sample.sample_uuid,
      sample_manifest_version: Manifest.version(),
      template_type: "computation",
      status: "compiled",
      method: sample.method,
      param_schema: sample.param_schema,
      example_request: sample.example_request,
      example_response: sample.example_response,
      validation_report: sample.validation_report
    }

    api =
      case Repo.get_by(Api, project_id: project.id, sample_uuid: sample.sample_uuid) do
        nil ->
          {:ok, api} = Apis.create_api(attrs)
          api

        %Api{} = existing ->
          {:ok, api} = Apis.update_api(existing, attrs)
          api
      end

    files = sample.files

    {:ok, _} =
      Files.upsert_files(
        api,
        [
          %{path: "/src/handler.ex", content: files.handler, file_type: "source"},
          %{path: "/src/helpers.ex", content: files.helpers, file_type: "source"},
          %{path: "/src/request_schema.ex", content: files.request_schema, file_type: "source"},
          %{path: "/src/response_schema.ex", content: files.response_schema, file_type: "source"},
          %{path: "/test/handler_test.ex", content: files.test, file_type: "test"},
          %{path: "/README.md", content: files.readme, file_type: "doc"}
        ],
        %{source: "template"}
      )

    api
  end

  defp upsert_flows!(project, user) do
    Manifest.list_by_kind(:flow)
    |> Enum.map(fn sample ->
      flow = upsert_flow!(project, user, sample)
      {sample.sample_uuid, flow}
    end)
    |> Map.new()
  end

  defp upsert_flow!(project, user, sample) do
    attrs = %{
      name: sample.name,
      description: sample.description,
      organization_id: project.organization_id,
      project_id: project.id,
      user_id: user && user.id,
      definition: sample.definition,
      sample_uuid: sample.sample_uuid,
      sample_manifest_version: Manifest.version()
    }

    flow =
      case Repo.get_by(Flow, project_id: project.id, sample_uuid: sample.sample_uuid) do
        nil ->
          {:ok, flow} = Flows.create_flow(attrs)
          flow

        %Flow{} = existing ->
          {:ok, flow} = Flows.update_flow(existing, Map.put(attrs, :status, existing.status))
          flow
      end

    case Flows.activate_flow(flow) do
      {:ok, active} -> active
      {:error, _reason} -> flow
    end
  end

  defp upsert_pages!(project, user) do
    page_samples = Manifest.list_by_kind(:page)

    pages_by_uuid =
      page_samples
      |> Enum.map(fn sample ->
        page = upsert_page!(project, user, sample, nil)
        {sample.sample_uuid, page}
      end)
      |> Map.new()

    Enum.each(page_samples, fn sample ->
      parent_id =
        sample
        |> Map.get(:parent_sample_uuid)
        |> then(fn uuid -> uuid && pages_by_uuid[uuid].id end)

      upsert_page!(project, user, sample, parent_id)
    end)

    length(page_samples)
  end

  defp upsert_page!(project, user, sample, parent_id) do
    attrs = %{
      title: sample.title || sample.name,
      content: sample.content,
      status: sample.status || "published",
      position: sample.position || 0,
      parent_id: parent_id,
      organization_id: project.organization_id,
      project_id: project.id,
      user_id: user && user.id,
      sample_uuid: sample.sample_uuid,
      sample_manifest_version: Manifest.version()
    }

    case Repo.get_by(Page, project_id: project.id, sample_uuid: sample.sample_uuid) do
      nil ->
        {:ok, page} = Pages.create_page(attrs)
        page

      %Page{} = existing ->
        {:ok, page} = Pages.update_page(existing, attrs)
        page
    end
  end

  defp upsert_playgrounds!(project, user, flow_by_uuid) do
    Manifest.list_by_kind(:playground)
    |> Enum.each(&upsert_playground!(project, user, &1, flow_by_uuid))
    |> then(fn _ -> length(Manifest.list_by_kind(:playground)) end)
  end

  defp upsert_playground!(project, user, sample, flow_by_uuid) do
    attrs = %{
      name: sample.name,
      description: sample.description,
      code: render_playground_code(sample.code, flow_by_uuid),
      organization_id: project.organization_id,
      project_id: project.id,
      user_id: user && user.id,
      sample_uuid: sample.sample_uuid,
      sample_manifest_version: Manifest.version()
    }

    case Repo.get_by(Playground, project_id: project.id, sample_uuid: sample.sample_uuid) do
      nil ->
        {:ok, playground} = Playgrounds.create_playground(attrs)
        playground

      %Playground{} = existing ->
        {:ok, playground} = Playgrounds.update_playground(existing, attrs)
        playground
    end
  end

  defp render_playground_code(code, flow_by_uuid) do
    Regex.replace(~r/\{\{flow:([0-9a-f-]+):webhook_token\}\}/, code, fn _match, sample_uuid ->
      case Map.get(flow_by_uuid, sample_uuid) do
        %{webhook_token: token} when is_binary(token) -> token
        _ -> "FLOW_TOKEN_NOT_FOUND"
      end
    end)
  end
end
