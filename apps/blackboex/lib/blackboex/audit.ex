defmodule Blackboex.Audit do
  @moduledoc """
  The Audit context. Records and queries operation-level audit logs.
  """

  alias Blackboex.Audit.{AuditLog, AuditQueries}
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

  @doc """
  Fire-and-forget audit log. When the Ecto sandbox is active (test env),
  runs synchronously to avoid connection ownership issues from detached tasks.
  In other envs spawns a detached task via LoggingSupervisor.
  """
  @spec log_async(String.t(), map()) :: :ok
  def log_async(action, attrs) do
    if Repo.config()[:pool] == Ecto.Adapters.SQL.Sandbox do
      log(action, attrs)
      :ok
    else
      Task.Supervisor.start_child(Blackboex.LoggingSupervisor, fn ->
        log(action, attrs)
      end)

      :ok
    end
  end

  @spec list_logs(binary(), keyword()) :: [AuditLog.t()]
  def list_logs(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    organization_id
    |> AuditQueries.for_organization(limit)
    |> Repo.all()
  end

  @spec list_user_logs(integer(), keyword()) :: [AuditLog.t()]
  def list_user_logs(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    user_id
    |> AuditQueries.for_user(limit)
    |> Repo.all()
  end

  @spec list_recent_activity(Ecto.UUID.t(), pos_integer()) :: [map()]
  def list_recent_activity(org_id, limit \\ 10) do
    org_id
    |> AuditQueries.for_organization(limit)
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
