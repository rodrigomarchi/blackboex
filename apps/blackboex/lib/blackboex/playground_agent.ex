defmodule Blackboex.PlaygroundAgent do
  @moduledoc """
  The PlaygroundAgent context. Orchestrates AI-powered chat that generates or
  edits the code of a Playground.

  Entry point `start/3` validates the plan's LLM generation quota, picks
  between generate/edit based on whether the playground already has code, and
  enqueues an Oban job (`KickoffWorker`) that sets up persistence and starts
  the `Session` GenServer.
  """

  alias Blackboex.Billing.Enforcement
  alias Blackboex.Organizations
  alias Blackboex.PlaygroundAgent.KickoffWorker
  alias Blackboex.Playgrounds.Playground

  @type scope :: %{user: %{id: term()}}

  @spec start(Playground.t(), scope(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, :limit_exceeded | :empty_message | term()}
  def start(%Playground{} = playground, scope, message) when is_binary(message) do
    case String.trim(message) do
      "" -> {:error, :empty_message}
      trimmed -> do_start(playground, scope, trimmed)
    end
  end

  defp do_start(playground, scope, message) do
    with {:ok, org} <- fetch_org(playground.organization_id),
         :ok <- check_enforcement(org) do
      run_type = if String.trim(playground.code || "") == "", do: "generate", else: "edit"

      args = %{
        "playground_id" => playground.id,
        "organization_id" => playground.organization_id,
        "project_id" => playground.project_id,
        "user_id" => user_id(scope),
        "run_type" => run_type,
        "trigger_message" => message,
        "code_before" => playground.code || ""
      }

      args
      |> KickoffWorker.new()
      |> Oban.insert()
    end
  end

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

  defp user_id(%{user: %{id: id}}), do: id
  defp user_id(%{user_id: id}), do: id
end
