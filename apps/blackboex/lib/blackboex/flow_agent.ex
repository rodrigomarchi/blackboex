defmodule Blackboex.FlowAgent do
  @moduledoc """
  The FlowAgent context. Orchestrates AI-powered chat that creates or edits
  the definition of a Flow.

  Entry point `start/3` validates org ownership and the plan's LLM generation
  quota, picks between generate/edit based on whether the flow already has a
  definition, and enqueues an Oban job (`KickoffWorker`) that sets up
  persistence and starts the `Session` GenServer.
  """

  alias Blackboex.Billing.Enforcement
  alias Blackboex.FlowAgent.KickoffWorker
  alias Blackboex.Flows.Flow
  alias Blackboex.Organizations

  @max_message_chars 10_000
  # Serialized flow definitions above this size are rejected before the LLM
  # call — otherwise a legitimately large flow can burn significant tokens on
  # every edit request.
  @max_definition_bytes 100_000

  @type scope :: %{optional(:organization) => map(), optional(:user) => map()}

  @spec start(Flow.t(), scope(), String.t()) ::
          {:ok, Oban.Job.t()}
          | {:error,
             :empty_message
             | :message_too_long
             | :forbidden
             | :limit_exceeded
             | :definition_too_large
             | :definition_invalid
             | term()}
  def start(%Flow{} = flow, scope, message) when is_binary(message) do
    case String.trim(message) do
      "" -> {:error, :empty_message}
      trimmed -> maybe_start(flow, scope, trimmed)
    end
  end

  defp maybe_start(_flow, _scope, trimmed) when byte_size(trimmed) > @max_message_chars do
    {:error, :message_too_long}
  end

  defp maybe_start(flow, scope, trimmed) do
    with :ok <- authorize(flow, scope),
         :ok <- check_definition_size(flow.definition),
         {:ok, org} <- fetch_org(flow.organization_id),
         :ok <- check_enforcement(org) do
      run_type = if empty_definition?(flow.definition), do: "generate", else: "edit"

      args = %{
        "flow_id" => flow.id,
        "organization_id" => flow.organization_id,
        "project_id" => flow.project_id,
        "user_id" => user_id(scope),
        "run_type" => run_type,
        "trigger_message" => trimmed,
        "definition_before" => flow.definition || %{}
      }

      args
      |> KickoffWorker.new()
      |> Oban.insert()
    end
  end

  defp check_definition_size(nil), do: :ok
  defp check_definition_size(def) when def == %{}, do: :ok

  defp check_definition_size(definition) when is_map(definition) do
    case Jason.encode(definition) do
      {:ok, json} when byte_size(json) <= @max_definition_bytes -> :ok
      {:ok, _json} -> {:error, :definition_too_large}
      {:error, _} -> {:error, :definition_invalid}
    end
  end

  defp authorize(flow, %{organization: %{id: org_id}}) when not is_nil(org_id) do
    if flow.organization_id == org_id, do: :ok, else: {:error, :forbidden}
  end

  defp authorize(_flow, _scope), do: {:error, :forbidden}

  defp check_enforcement(org) do
    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _} -> :ok
      {:error, :limit_exceeded, _details} -> {:error, :limit_exceeded}
    end
  end

  defp fetch_org(org_id) do
    case Organizations.get_organization(org_id) do
      nil -> {:error, :organization_not_found}
      org -> {:ok, org}
    end
  end

  defp empty_definition?(nil), do: true
  defp empty_definition?(def) when def == %{}, do: true
  defp empty_definition?(%{"nodes" => []}), do: true
  defp empty_definition?(_), do: false

  defp user_id(%{user: %{id: id}}), do: id
  defp user_id(%{user_id: id}), do: id
  defp user_id(_), do: nil
end
