defmodule Blackboex.Apis.Conversations do
  @moduledoc """
  Context for managing API chat conversations.
  Each API has at most one conversation for iterative LLM editing.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.ApiConversation
  alias Blackboex.Repo

  @valid_roles ApiConversation.valid_roles()

  @spec get_or_create_conversation(Ecto.UUID.t()) ::
          {:ok, ApiConversation.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_conversation(api_id) do
    case Repo.get_by(ApiConversation, api_id: api_id) do
      nil ->
        %ApiConversation{}
        |> ApiConversation.changeset(%{api_id: api_id})
        |> Repo.insert()

      conversation ->
        {:ok, conversation}
    end
  end

  @spec append_message(ApiConversation.t(), String.t(), String.t(), map()) ::
          {:ok, ApiConversation.t()} | {:error, :invalid_role | :too_many_messages}
  def append_message(%ApiConversation{} = conversation, role, content, metadata \\ %{}) do
    cond do
      role not in @valid_roles ->
        {:error, :invalid_role}

      length(conversation.messages) >= ApiConversation.max_messages() ->
        {:error, :too_many_messages}

      true ->
        message = %{
          "role" => role,
          "content" => content,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "metadata" => metadata
        }

        do_append(conversation, message)
    end
  end

  @spec clear_conversation(ApiConversation.t()) ::
          {:ok, ApiConversation.t()} | {:error, Ecto.Changeset.t()}
  def clear_conversation(%ApiConversation{} = conversation) do
    conversation
    |> ApiConversation.changeset(%{messages: []})
    |> Repo.update()
  end

  # Atomic append using SELECT FOR UPDATE to prevent race conditions.
  # The row lock ensures concurrent appends are serialized.
  defp do_append(%ApiConversation{id: id}, message) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:lock, fn repo, _changes ->
      conv =
        from(c in ApiConversation, where: c.id == ^id, lock: "FOR UPDATE")
        |> repo.one!()

      {:ok, conv}
    end)
    |> Ecto.Multi.run(:update, fn repo, %{lock: conv} ->
      updated_messages = conv.messages ++ [message]

      conv
      |> ApiConversation.changeset(%{messages: updated_messages})
      |> repo.update()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{update: updated}} -> {:ok, updated}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end
end
