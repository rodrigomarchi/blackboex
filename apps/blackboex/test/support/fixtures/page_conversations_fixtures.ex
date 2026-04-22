defmodule Blackboex.PageConversationsFixtures do
  @moduledoc """
  Test helpers for creating PageConversation, PageRun, and PageEvent entities.
  Uses `Repo` directly to avoid coupling fixtures to the facade — the facade's
  own tests can therefore consume these fixtures without circular dependency.
  """

  import Ecto.Query, only: [from: 2]

  alias Blackboex.PageConversations.PageConversation
  alias Blackboex.PageConversations.PageEvent
  alias Blackboex.PageConversations.PageRun
  alias Blackboex.Repo

  @doc """
  Gets or creates an active PageConversation for the given page.

  Options:
    * `:page` — the Page (auto-created via `PagesFixtures.page_fixture/1` if absent)
    * `:user`, `:org`, `:project` — forwarded to page auto-creation

  Returns the PageConversation struct.
  """
  @spec page_conversation_fixture(map()) :: PageConversation.t()
  def page_conversation_fixture(attrs \\ %{}) do
    page = attrs[:page] || Blackboex.PagesFixtures.page_fixture(Map.take(attrs, [:user, :org]))

    case Repo.get_by(PageConversation, page_id: page.id, status: "active") do
      %PageConversation{} = existing ->
        existing

      nil ->
        {:ok, conv} =
          %PageConversation{}
          |> PageConversation.changeset(%{
            page_id: page.id,
            organization_id: page.organization_id,
            project_id: page.project_id,
            status: "active"
          })
          |> Repo.insert()

        conv
    end
  end

  @doc """
  Creates a PageRun for the given (or auto-created) conversation.

  Options:
    * `:conversation` — parent PageConversation (auto-created if absent)
    * `:user` — owning User (auto-created if absent)
    * `:run_type` — default `"edit"`
    * `:status` — default `"pending"`
    * `:trigger_message`, `:content_before` — passed through

  Returns the PageRun struct.
  """
  @spec page_run_fixture(map()) :: PageRun.t()
  def page_run_fixture(attrs \\ %{}) do
    conversation =
      attrs[:conversation] ||
        page_conversation_fixture(Map.take(attrs, [:page, :user, :org, :project]))

    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()

    known_keys = [:conversation, :page, :user, :org, :project]

    base = %{
      conversation_id: conversation.id,
      page_id: conversation.page_id,
      organization_id: conversation.organization_id,
      user_id: user.id,
      run_type: "edit",
      status: "pending",
      trigger_message: "edit my page",
      content_before: ""
    }

    {:ok, run} =
      %PageRun{}
      |> PageRun.changeset(Map.merge(base, Map.drop(attrs, known_keys)))
      |> Repo.insert()

    run
  end

  @doc """
  Creates a PageEvent for the given (or auto-created) run.

  Auto-assigns the next `sequence` per run if not provided.
  """
  @spec page_event_fixture(map()) :: PageEvent.t()
  def page_event_fixture(attrs \\ %{}) do
    run =
      attrs[:run] || page_run_fixture(Map.take(attrs, [:conversation, :user, :org, :project]))

    known_keys = [:run, :conversation, :user, :org, :project]
    extra = Map.drop(attrs, known_keys)

    sequence = Map.get(extra, :sequence, next_sequence(run.id))

    base = %{
      run_id: run.id,
      sequence: sequence,
      event_type: "user_message",
      content: "hello",
      metadata: %{}
    }

    final_attrs =
      base
      |> Map.merge(Map.drop(extra, [:sequence]))
      |> Map.put(:sequence, sequence)

    {:ok, event} =
      %PageEvent{}
      |> PageEvent.changeset(final_attrs)
      |> Repo.insert()

    event
  end

  defp next_sequence(run_id) do
    max =
      Repo.one(from e in PageEvent, where: e.run_id == ^run_id, select: max(e.sequence)) || -1

    max + 1
  end
end
