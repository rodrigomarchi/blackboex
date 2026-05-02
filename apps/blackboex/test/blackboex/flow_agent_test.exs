defmodule Blackboex.FlowAgentTest do
  use Blackboex.DataCase, async: true
  use Oban.Testing, repo: Blackboex.Repo

  # Integration tests start FlowAgent.Session GenServers whose async chain
  # tasks can finish after the test exits — leaving benign sandbox-owner
  # errors in the log. Capture so the suite output stays clean.
  @moduletag :capture_log

  alias Blackboex.FlowAgent
  alias Blackboex.FlowAgent.KickoffWorker

  setup [:create_user_and_org]

  defp scope_for(user, org), do: %{user: %{id: user.id}, organization: %{id: org.id}}

  describe "start/3 validation" do
    test "rejects empty message", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert {:error, :empty_message} = FlowAgent.start(flow, scope_for(user, org), "   ")
    end

    test "rejects message longer than 10_000 chars", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      huge = String.duplicate("a", 10_001)
      assert {:error, :message_too_long} = FlowAgent.start(flow, scope_for(user, org), huge)
    end

    test "rejects when scope org does not own the flow", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      other = org_fixture(%{user: user})
      assert {:error, :forbidden} = FlowAgent.start(flow, scope_for(user, other), "oi")
    end

    test "rejects when current definition exceeds the size cap",
         %{user: user, org: org} do
      # Construct a flow with a valid but oversized definition (~200KB of noise
      # in elixir_code `code` fields). The size cap rejects this before the
      # LLM is hit.
      big_code = String.duplicate("a", 110_000)

      big_definition = %{
        "version" => "1.0",
        "nodes" => [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{}
          },
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => big_code}
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{}
          }
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          },
          %{
            "id" => "e2",
            "source" => "n2",
            "source_port" => 0,
            "target" => "n3",
            "target_port" => 0
          }
        ]
      }

      flow = flow_fixture(%{user: user, org: org})
      {:ok, flow} = Blackboex.Flows.update_definition(flow, big_definition)

      assert {:error, :definition_too_large} =
               FlowAgent.start(flow, scope_for(user, org), "edite algo")
    end
  end

  describe "start/3 run_type selection" do
    test "picks :generate when flow.definition is empty", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert {:ok, job} = FlowAgent.start(flow, scope_for(user, org), "crie um hello world")
      assert job.args["run_type"] == "generate"
      assert job.args["flow_id"] == flow.id
      assert job.args["trigger_message"] == "crie um hello world"
    end

    test "picks :edit when flow.definition has nodes", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})

      {:ok, flow} =
        Blackboex.Flows.update_definition(flow, %{
          "version" => "1.0",
          "nodes" => [
            %{
              "id" => "n1",
              "type" => "start",
              "position" => %{"x" => 0, "y" => 0},
              "data" => %{}
            },
            %{
              "id" => "n2",
              "type" => "end",
              "position" => %{"x" => 200, "y" => 0},
              "data" => %{}
            }
          ],
          "edges" => [
            %{
              "id" => "e1",
              "source" => "n1",
              "source_port" => 0,
              "target" => "n2",
              "target_port" => 0
            }
          ]
        })

      assert {:ok, job} = FlowAgent.start(flow, scope_for(user, org), "adicione um delay")
      assert job.args["run_type"] == "edit"
      assert is_map(job.args["definition_before"])
      assert job.args["definition_before"]["version"] == "1.0"
    end
  end

  describe "start/3 enqueues KickoffWorker" do
    test "returns {:ok, %Oban.Job{}} with KickoffWorker worker", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert {:ok, job} = FlowAgent.start(flow, scope_for(user, org), "oi")
      assert job.worker == inspect(KickoffWorker) |> String.replace_prefix("Elixir.", "")

      assert_enqueued(
        worker: KickoffWorker,
        args: %{"flow_id" => flow.id, "trigger_message" => "oi"}
      )
    end
  end
end
