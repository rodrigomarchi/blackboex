defmodule Blackboex.PageAgentIntegrationTest do
  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  @moduletag :integration
  @moduletag :capture_log

  alias Blackboex.LLM.ClientMock
  alias Blackboex.PageAgent
  alias Blackboex.PageAgent.StreamManager
  alias Blackboex.PageConversations
  alias Blackboex.Pages

  @canned """
  Aqui vai o conteúdo:
  ~~~markdown
  # Título AI

  Parágrafo gerado pelo agente.
  ~~~
  Resumo: rascunho inicial.
  """

  setup do
    {user, org} = user_and_org_fixture()
    page = page_fixture(%{user: user, org: org})
    scope = %{user: user, organization: org}

    Phoenix.PubSub.subscribe(
      Blackboex.PubSub,
      StreamManager.page_topic(org.id, page.id)
    )

    Mox.stub(ClientMock, :stream_text, fn _prompt, _opts ->
      tokens = String.graphemes(@canned)
      {:ok, Stream.map(tokens, & &1)}
    end)

    Mox.stub(ClientMock, :generate_text, fn _p, _o ->
      {:ok, %{content: @canned, usage: %{}}}
    end)

    Mox.set_mox_global()

    %{user: user, org: org, page: page, scope: scope}
  end

  test "end-to-end: start → kickoff → session → chain → page.content updated",
       %{page: page, scope: scope} do
    assert {:ok, _job} = PageAgent.start(page, scope, "escreve intro")

    # Run the Oban kickoff job inline.
    assert %{success: 1} = Oban.drain_queue(queue: :page_agent)

    assert_receive {:run_started, %{run_id: _run_id, page_id: _}}, 2_000
    assert_receive {:run_completed, %{content: content, summary: summary}}, 5_000

    assert content =~ "# Título AI"
    assert summary =~ "rascunho"

    updated = Pages.get_page(page.project_id, page.id)
    assert updated.content =~ "# Título AI"

    conv = PageConversations.get_active_conversation(page.id)
    [run] = PageConversations.list_runs(conv.id)
    assert run.status == "completed"

    events = PageConversations.list_events(run.id)
    types = Enum.map(events, & &1.event_type)
    assert "user_message" in types
    assert "completed" in types

    conv = PageConversations.get_conversation(conv.id)
    assert conv.total_runs >= 1
  end
end
