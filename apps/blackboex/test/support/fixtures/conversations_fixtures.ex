defmodule Blackboex.ConversationsFixtures do
  @moduledoc """
  Test helpers for creating conversation entities.
  """

  alias Blackboex.Conversations

  @doc """
  Gets or creates a conversation for the given API and org.

  Returns the conversation struct.
  """
  @spec conversation_fixture(Ecto.UUID.t(), Ecto.UUID.t()) ::
          Blackboex.Conversations.Conversation.t()
  def conversation_fixture(api_id, org_id) do
    {:ok, conversation} = Conversations.get_or_create_conversation(api_id, org_id)
    conversation
  end

  @doc """
  Creates a run for the given context.

  ## Required keys in attrs

    * `:conversation_id`
    * `:api_id`
    * `:user_id`
    * `:organization_id`

  ## Optional

    * `:run_type` - (default: "generation")
    * `:status` - (default: "running")
    * Any other Run fields

  Returns the run struct.
  """
  @spec run_fixture(map()) :: Blackboex.Conversations.Run.t()
  def run_fixture(attrs) do
    {:ok, run} =
      Conversations.create_run(
        Map.merge(
          %{
            run_type: "generation",
            status: "running"
          },
          attrs
        )
      )

    run
  end
end
