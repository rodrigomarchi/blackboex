defmodule Blackboex.Flows do
  @moduledoc """
  The Flows context. Manages visual workflow flows created by users.

  Each flow stores its graph definition as JSONB (Drawflow export format).
  """

  alias Blackboex.Billing.Enforcement
  alias Blackboex.Flows.Flow
  alias Blackboex.Flows.FlowQueries
  alias Blackboex.Organizations
  alias Blackboex.Repo

  # ── Flow CRUD ──────────────────────────────────────────────

  @spec create_flow(map()) ::
          {:ok, Flow.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :limit_exceeded, map()}
  def create_flow(attrs) do
    org_id = attrs[:organization_id] || attrs["organization_id"]

    if org_id do
      create_flow_with_lock(attrs, org_id)
    else
      %Flow{}
      |> Flow.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec list_flows(Ecto.UUID.t()) :: [Flow.t()]
  def list_flows(organization_id) do
    organization_id |> FlowQueries.list_for_org() |> Repo.all()
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
    |> Flow.changeset(attrs)
    |> Repo.update()
  end

  @spec update_definition(Flow.t(), map()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def update_definition(%Flow{} = flow, definition) do
    flow
    |> Flow.definition_changeset(%{definition: definition})
    |> Repo.update()
  end

  @spec delete_flow(Flow.t()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def delete_flow(%Flow{} = flow) do
    Repo.delete(flow)
  end

  @spec get_flow_by_slug(Ecto.UUID.t(), String.t()) :: Flow.t() | nil
  def get_flow_by_slug(organization_id, slug) do
    organization_id |> FlowQueries.by_org_and_slug(slug) |> Repo.one()
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
        attrs = Map.put(attrs, :definition, template.definition)
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

  defp check_and_insert_flow(attrs, org_id) do
    case Organizations.get_organization(org_id) do
      nil ->
        insert_flow!(attrs)

      org ->
        case Enforcement.check_limit(org, :create_flow) do
          {:ok, _remaining} -> insert_flow!(attrs)
          {:error, :limit_exceeded, details} -> Repo.rollback({:limit_exceeded, details})
        end
    end
  end

  defp insert_flow!(attrs) do
    %Flow{}
    |> Flow.changeset(attrs)
    |> Repo.insert!()
  end
end
