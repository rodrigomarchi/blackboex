defmodule Blackboex.Audit do
  @moduledoc """
  The Audit context. Records and queries operation-level audit logs.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Audit.AuditLog
  alias Blackboex.Repo

  @doc """
  Sets ExAudit tracking data for the current process.
  Wrapper to keep ExAudit calls within the domain app.
  """
  @spec track(keyword()) :: :ok
  def track(data) do
    ExAudit.track(data)
  end

  @spec log(String.t(), map()) :: {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def log(action, attrs \\ %{}) do
    %AuditLog{}
    |> AuditLog.changeset(Map.put(attrs, :action, action))
    |> Repo.insert()
  end

  @spec list_logs(binary(), keyword()) :: [AuditLog.t()]
  def list_logs(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    AuditLog
    |> where([a], a.organization_id == ^organization_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_user_logs(integer(), keyword()) :: [AuditLog.t()]
  def list_user_logs(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    AuditLog
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_recent_activity(Ecto.UUID.t(), pos_integer()) :: [map()]
  def list_recent_activity(org_id, limit \\ 10) do
    AuditLog
    |> where([a], a.organization_id == ^org_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&format_activity/1)
  end

  defp format_activity(%AuditLog{} = log) do
    %{
      action: log.action,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      metadata: log.metadata || %{},
      timestamp: log.inserted_at
    }
  end
end
