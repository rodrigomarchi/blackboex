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
