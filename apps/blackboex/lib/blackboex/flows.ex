defmodule Blackboex.Flows do
  @moduledoc """
  The Flows context. Manages visual workflow flows created by users.

  Each flow stores its graph definition as JSONB (Drawflow export format).
  """

  alias Blackboex.Flows.Flow
  alias Blackboex.Flows.FlowQueries
  alias Blackboex.Projects
  alias Blackboex.Repo

  # ── Flow CRUD ──────────────────────────────────────────────

  @spec create_flow(map()) ::
          {:ok, Flow.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :forbidden}
          | {:error, :limit_exceeded, map()}
  def create_flow(attrs) do
    org_id = attrs[:organization_id] || attrs["organization_id"]
    project_id = attrs[:project_id] || attrs["project_id"]

    with :ok <- ensure_project_in_org(project_id, org_id) do
      if org_id do
        create_flow_with_lock(attrs, org_id)
      else
        %Flow{}
        |> Flow.changeset(attrs)
        |> Repo.insert()
      end
    end
  end

  @spec list_flows(Ecto.UUID.t()) :: [Flow.t()]
  def list_flows(organization_id) do
    organization_id |> FlowQueries.list_for_org() |> Repo.all()
  end

  @spec list_flows_for_project(Ecto.UUID.t()) :: [Flow.t()]
  def list_flows_for_project(project_id) do
    project_id |> FlowQueries.list_for_project() |> Repo.all()
  end

  @spec list_for_project(Ecto.UUID.t(), keyword()) :: [Flow.t()]
  def list_for_project(project_id, opts \\ []) do
    project_id |> FlowQueries.list_for_project_sorted(opts) |> Repo.all()
  end

  @spec list_flows(Ecto.UUID.t(), keyword()) :: [Flow.t()]
  def list_flows(organization_id, opts) do
    query = FlowQueries.list_for_org(organization_id)

    query =
      case Keyword.get(opts, :search) do
        nil -> query
        "" -> query
        term -> FlowQueries.search(query, term)
      end

    Repo.all(query)
  end

  @spec get_flow(Ecto.UUID.t(), Ecto.UUID.t()) :: Flow.t() | nil
  def get_flow(organization_id, flow_id) do
    organization_id |> FlowQueries.by_org_and_id(flow_id) |> Repo.one()
  end

  @spec update_flow(Flow.t(), map()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def update_flow(%Flow{} = flow, attrs) do
    flow
    |> Flow.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves a Flow to a different project within the same organization.

  Validates that `new_project_id` belongs to the same org as the flow.
  """
  @spec move_flow(Flow.t(), Ecto.UUID.t()) ::
          {:ok, Flow.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def move_flow(%Flow{} = flow, new_project_id) do
    with :ok <- ensure_project_in_org(new_project_id, flow.organization_id) do
      flow
      |> Flow.move_project_changeset(%{project_id: new_project_id})
      |> Repo.update()
    end
  end

  @spec update_definition(Flow.t(), map()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def update_definition(%Flow{} = flow, definition) do
    flow
    |> Flow.definition_changeset(%{definition: definition})
    |> Repo.update()
  end

  @doc """
  Persists a definition produced by the Flow AI agent. Scoped variant of
  `update_definition/2` that enforces organization ownership before touching
  the row. Used by `FlowAgent.ChainRunner` after a successful LLM run.
  """
  @spec record_ai_edit(Flow.t(), map(), map()) ::
          {:ok, Flow.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def record_ai_edit(%Flow{} = flow, new_definition, %{organization: %{id: org_id}})
      when is_map(new_definition) do
    if flow.organization_id == org_id do
      update_definition(flow, new_definition)
    else
      {:error, :unauthorized}
    end
  end

  @spec delete_flow(Flow.t()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def delete_flow(%Flow{} = flow) do
    Repo.delete(flow)
  end

  @doc """
  Fetches a Flow by organization_id and flow_id. Returns `nil` when not found or
  the flow does not belong to the given organization.
  """
  @spec get_for_org(Ecto.UUID.t(), Ecto.UUID.t()) :: Flow.t() | nil
  def get_for_org(org_id, flow_id) do
    org_id |> FlowQueries.by_org_and_id_only(flow_id) |> Repo.one()
  end

  @spec get_flow_by_slug(Ecto.UUID.t(), String.t()) :: Flow.t() | nil
  def get_flow_by_slug(organization_id, slug) do
    organization_id |> FlowQueries.by_org_and_slug(slug) |> Repo.one()
  end

  @spec get_flow_by_project_slug(Ecto.UUID.t(), String.t()) :: Flow.t() | nil
  def get_flow_by_project_slug(project_id, slug) do
    project_id |> FlowQueries.by_project_and_slug(slug) |> Repo.one()
  end

  # ── Activation ─────────────────────────────────────────────

  @spec activate_flow(Flow.t()) :: {:ok, Flow.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def activate_flow(%Flow{} = flow) do
    alias Blackboex.FlowExecutor.{BlackboexFlow, CodeValidator, DefinitionParser}

    definition = flow.definition || %{}

    with :ok <- BlackboexFlow.validate(definition),
         {:ok, parsed} <- DefinitionParser.parse(definition),
         :ok <- CodeValidator.validate_flow(parsed) do
      update_flow(flow, %{status: "active"})
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, errors} when is_list(errors) -> {:error, format_validation_errors(errors)}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @spec deactivate_flow(Flow.t()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def deactivate_flow(%Flow{} = flow) do
    update_flow(flow, %{status: "draft"})
  end

  defp format_validation_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(fn
      {node_id, field, reason} -> "#{node_id}.#{field}: #{reason}"
      other -> inspect(other)
    end)
    |> Enum.join("; ")
  end

  # ── Webhook Token ─────────────────────────────────────────

  @spec get_flow_by_token!(String.t()) :: Flow.t()
  def get_flow_by_token!(token) do
    Repo.get_by!(Flow, webhook_token: token)
  end

  @spec regenerate_webhook_token(Flow.t()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def regenerate_webhook_token(%Flow{} = flow) do
    flow
    |> Flow.webhook_token_changeset()
    |> Repo.update()
  end

  # ── Templates ──────────────────────────────────────────────

  @spec create_flow_from_template(map(), String.t()) ::
          {:ok, Flow.t()}
          | {:error, :template_not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, :limit_exceeded, map()}
  def create_flow_from_template(attrs, template_id) do
    alias Blackboex.Flows.Templates

    case Templates.get(template_id) do
      nil ->
        {:error, :template_not_found}

      template ->
        attrs =
          Map.merge(attrs, %{
            definition: template.definition
          })

        create_flow(attrs)
    end
  end

  # ── Private ────────────────────────────────────────────────

  defp create_flow_with_lock(attrs, org_id) do
    Repo.transaction(fn ->
      acquire_flow_creation_lock(org_id)
      check_and_insert_flow(attrs, org_id)
    end)
    |> case do
      {:ok, flow} -> {:ok, flow}
      {:error, {:limit_exceeded, details}} -> {:error, :limit_exceeded, details}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  rescue
    e in Ecto.InvalidChangesetError -> {:error, e.changeset}
  end

  defp acquire_flow_creation_lock(org_id) do
    lock_key = :erlang.phash2({"create_flow", org_id})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])
  end

  defp check_and_insert_flow(attrs, _org_id) do
    insert_flow!(attrs)
  end

  defp insert_flow!(attrs) do
    %Flow{}
    |> Flow.changeset(attrs)
    |> Repo.insert!()
  end

  defp ensure_project_in_org(nil, _org_id), do: :ok
  defp ensure_project_in_org(_project_id, nil), do: :ok

  defp ensure_project_in_org(project_id, org_id) do
    case Projects.get_project(org_id, project_id) do
      nil -> {:error, :forbidden}
      _project -> :ok
    end
  end
end
