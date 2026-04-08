defmodule Blackboex.Agent do
  @moduledoc """
  The Agent context. Orchestrates AI-powered code generation and editing.

  Provides the public entry points for starting agent generation and edit jobs.
  Internally delegates to `Agent.KickoffWorker` for Oban job enqueueing and
  `Agent.Session` for stateful pipeline execution.
  """

  alias Blackboex.Agent.KickoffWorker
  alias Blackboex.Apis
  alias Blackboex.Apis.Api

  @spec start_generation(Api.t(), String.t(), String.t() | integer()) ::
          {:ok, String.t()} | {:error, term()}
  def start_generation(%Api{} = api, description, user_id) do
    args = %{
      "api_id" => api.id,
      "organization_id" => api.organization_id,
      "user_id" => user_id,
      "run_type" => "generation",
      "trigger_message" => description
    }

    Apis.update_api(api, %{generation_status: "generating"})

    case args |> KickoffWorker.new() |> Oban.insert() do
      {:ok, _job} -> {:ok, api.id}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_edit(Api.t(), String.t(), String.t() | integer()) ::
          {:ok, String.t()} | {:error, term()}
  def start_edit(%Api{} = api, instruction, user_id) do
    files = Apis.list_files(api.id)

    current_files =
      Enum.map(files, fn f ->
        %{"path" => f.path, "content" => f.content || "", "file_type" => f.file_type}
      end)

    args = %{
      "api_id" => api.id,
      "organization_id" => api.organization_id,
      "user_id" => user_id,
      "run_type" => "edit",
      "trigger_message" => instruction,
      "current_files" => current_files
    }

    case args |> KickoffWorker.new() |> Oban.insert() do
      {:ok, _job} -> {:ok, api.id}
      {:error, reason} -> {:error, reason}
    end
  end
end
