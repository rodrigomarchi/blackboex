defmodule Blackboex.PageAgent do
  @moduledoc """
  The PageAgent context. Orchestrates AI-powered chat that generates or edits
  the markdown content of a Page.

  Entry point `start/3` validates the plan's LLM generation quota, picks
  between generate/edit based on whether the page already has content, checks
  organization ownership (defense-in-depth IDOR), and enqueues an Oban job
  (`KickoffWorker`) that sets up persistence and starts the `Session`.
  """

  alias Blackboex.PageAgent.KickoffWorker
  alias Blackboex.Pages.Page

  @type scope :: %{user: %{id: term()}, organization: %{id: term()}}

  @max_message_chars 10_000

  @spec start(Page.t(), scope(), String.t()) ::
          {:ok, Oban.Job.t()}
          | {:error,
             :empty_message
             | :message_too_long
             | :unauthorized
             | :agent_busy
             | term()}
  def start(%Page{} = page, scope, message) when is_binary(message) do
    cond do
      String.trim(message) == "" ->
        {:error, :empty_message}

      String.length(message) > @max_message_chars ->
        {:error, :message_too_long}

      true ->
        do_start(page, scope, String.trim(message))
    end
  end

  defp do_start(page, scope, message) do
    with :ok <- authorize(page, scope) do
      run_type = if String.trim(page.content || "") == "", do: "generate", else: "edit"

      # Note: content_before is NOT in Oban args (would bloat the queue with up
      # to 1MB JSON per request). The worker reads it fresh from the DB so the
      # LLM operates on the latest content even if the job sits in the queue.
      args = %{
        "page_id" => page.id,
        "organization_id" => page.organization_id,
        "project_id" => page.project_id,
        "user_id" => user_id(scope),
        "run_type" => run_type,
        "trigger_message" => message
      }

      case args |> KickoffWorker.new() |> Oban.insert() do
        {:ok, %Oban.Job{conflict?: true}} -> {:error, :agent_busy}
        {:ok, job} -> {:ok, job}
        other -> other
      end
    end
  end

  defp authorize(%Page{organization_id: page_org_id}, %{organization: %{id: scope_org_id}})
       when page_org_id == scope_org_id,
       do: :ok

  defp authorize(_page, _scope), do: {:error, :unauthorized}

  defp user_id(%{user: %{id: id}}), do: id
  defp user_id(%{user_id: id}), do: id
end
