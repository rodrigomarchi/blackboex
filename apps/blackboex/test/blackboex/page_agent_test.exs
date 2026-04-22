defmodule Blackboex.PageAgentTest do
  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  @moduletag :unit

  alias Blackboex.PageAgent

  setup do
    {user, org} = user_and_org_fixture()
    scope = %{user: user, organization: org}
    %{user: user, org: org, scope: scope}
  end

  describe "start/3" do
    test "empty content page enqueues with run_type generate", %{
      user: user,
      org: org,
      scope: scope
    } do
      page = page_fixture(%{user: user, org: org, content: ""})

      assert {:ok, %Oban.Job{}} = PageAgent.start(page, scope, "escreva algo")

      assert_enqueued(
        worker: Blackboex.PageAgent.KickoffWorker,
        args: %{"page_id" => page.id, "run_type" => "generate"}
      )
    end

    test "non-empty content page enqueues with run_type edit", %{
      user: user,
      org: org,
      scope: scope
    } do
      page = page_fixture(%{user: user, org: org, content: "# existe"})

      assert {:ok, _} = PageAgent.start(page, scope, "melhora")

      assert_enqueued(
        worker: Blackboex.PageAgent.KickoffWorker,
        args: %{"page_id" => page.id, "run_type" => "edit"}
      )
    end

    test "empty message returns :empty_message", %{user: user, org: org, scope: scope} do
      page = page_fixture(%{user: user, org: org})
      assert {:error, :empty_message} = PageAgent.start(page, scope, "")

      refute_enqueued(worker: Blackboex.PageAgent.KickoffWorker)
    end

    test "whitespace-only message returns :empty_message", %{
      user: user,
      org: org,
      scope: scope
    } do
      page = page_fixture(%{user: user, org: org})
      assert {:error, :empty_message} = PageAgent.start(page, scope, "   \n\t  ")
    end

    test "cross-org scope returns :unauthorized (IDOR)", %{user: user} do
      other_org = org_fixture(%{user: user})
      other_page = page_fixture(%{user: user, org: other_org})

      {_u2, org} = user_and_org_fixture()
      scope = %{user: user, organization: org}

      assert {:error, :unauthorized} = PageAgent.start(other_page, scope, "olá")
    end

    test "job args include trigger_message and user_id (content read fresh by worker)", %{
      user: user,
      org: org,
      scope: scope
    } do
      page = page_fixture(%{user: user, org: org, content: "# hello"})
      {:ok, _job} = PageAgent.start(page, scope, "traduz")

      assert_enqueued(
        worker: Blackboex.PageAgent.KickoffWorker,
        args: %{
          "page_id" => page.id,
          "trigger_message" => "traduz",
          "user_id" => user.id
        }
      )
    end

    test "rejects messages over the 10k char limit", %{user: user, org: org, scope: scope} do
      page = page_fixture(%{user: user, org: org})
      huge = String.duplicate("a", 10_001)
      assert {:error, :message_too_long} = PageAgent.start(page, scope, huge)
      refute_enqueued(worker: Blackboex.PageAgent.KickoffWorker)
    end

    test "returns {:ok, %Oban.Job{}}", %{user: user, org: org, scope: scope} do
      page = page_fixture(%{user: user, org: org})
      assert {:ok, %Oban.Job{}} = PageAgent.start(page, scope, "go")
    end

    test "second concurrent message returns :agent_busy (no silent dedup)", %{
      user: user,
      org: org,
      scope: scope
    } do
      page = page_fixture(%{user: user, org: org})

      assert {:ok, %Oban.Job{}} = PageAgent.start(page, scope, "primeiro")
      assert {:error, :agent_busy} = PageAgent.start(page, scope, "segundo")
    end
  end
end
