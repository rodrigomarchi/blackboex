defmodule Blackboex.Apis.ApiConversation do
  @moduledoc """
  Schema for API chat conversations. Each API has at most one active conversation
  that stores the message history for conversational editing with the LLM.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_roles ~w(user assistant)
  @max_messages 500

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_conversations" do
    field :messages, {:array, :map}, default: []
    field :metadata, :map, default: %{}

    belongs_to :api, Blackboex.Apis.Api

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:api_id, :messages, :metadata])
    |> validate_required([:api_id])
    |> validate_messages()
    |> unique_constraint(:api_id)
  end

  @spec valid_roles() :: [String.t()]
  def valid_roles, do: @valid_roles

  @spec max_messages() :: integer()
  def max_messages, do: @max_messages

  defp validate_messages(changeset) do
    case get_change(changeset, :messages) do
      nil ->
        changeset

      messages ->
        cond do
          not valid_message_roles?(messages) ->
            add_error(
              changeset,
              :messages,
              "contains invalid role (must be: #{Enum.join(@valid_roles, ", ")})"
            )

          length(messages) > @max_messages ->
            add_error(changeset, :messages, "exceeds maximum of #{@max_messages} messages")

          true ->
            changeset
        end
    end
  end

  defp valid_message_roles?(messages) do
    Enum.all?(messages, fn
      %{"role" => role} -> role in @valid_roles
      _ -> true
    end)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
