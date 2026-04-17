defmodule Blackboex.LlmFixtures do
  @moduledoc """
  Test helpers for creating LLM usage entities.
  """

  alias Blackboex.LLM.Usage, as: LlmUsage
  alias Blackboex.Repo

  @doc """
  Inserts an LLM usage row.

  ## Required

    * `:project_id` - the project ID

  ## Optional

    * `:organization_id` - the organization ID
    * `:provider` - LLM provider (default: "openai")
    * `:model` - model name (default: "gpt-4o-mini")
    * `:operation` - operation type (default: "chat")
    * `:input_tokens` - input tokens (default: 100)
    * `:output_tokens` - output tokens (default: 50)
    * `:cost_cents` - cost in cents (default: 1)
    * `:duration_ms` - duration (default: 100)
    * `:inserted_at` - timestamp override (set after insert if provided)

  Returns the LLM usage struct.
  """
  @spec llm_usage_fixture(map()) :: LlmUsage.t()
  def llm_usage_fixture(attrs \\ %{}) do
    {inserted_at, attrs} = Map.pop(attrs, :inserted_at)

    user_id =
      Map.get_lazy(attrs, :user_id, fn ->
        Blackboex.AccountsFixtures.user_fixture().id
      end)

    attrs = Map.put(attrs, :user_id, user_id)

    usage =
      %LlmUsage{}
      |> LlmUsage.changeset(
        Map.merge(
          %{
            provider: "openai",
            model: "gpt-4o-mini",
            operation: "chat",
            input_tokens: 100,
            output_tokens: 50,
            cost_cents: 1,
            duration_ms: 100
          },
          attrs
        )
      )
      |> Repo.insert!()

    case inserted_at do
      nil ->
        usage

      %DateTime{} = dt ->
        naive = DateTime.to_naive(dt) |> NaiveDateTime.truncate(:second)

        usage
        |> Ecto.Changeset.change(%{inserted_at: naive})
        |> Repo.update!()
    end
  end
end
