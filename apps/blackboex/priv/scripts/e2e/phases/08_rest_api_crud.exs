defmodule E2E.Phase.RestApiCrud do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 8: REST API CRUD (JSONPlaceholder)"))
    flow = create_and_activate_template("rest_api_crud", "E2E RestCrud", user, org)

    [
      run_test("CRUD: POST creates resource, GET reads back", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "title" => "E2E Test Post",
            "body" => "Testing flow HTTP CRUD",
            "userId" => 1
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        # POST to jsonplaceholder returns 201
        assert_eq!(output["create_status"], 201, "create_status")
        assert_present!(output["created_id"], "created_id")
        # GET /posts/1 returns real post with title
        assert_eq!(output["read_status"], 200, "read_status")
        assert_present!(output["read_title"], "read_title not empty")
        assert_eq!(output["method_used"], "POST+GET", "method_used")
        :ok
      end),
      run_test("CRUD: body_template interpolates state values", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "title" => "Interpolation Test",
            "body" => "Check body template",
            "userId" => 42
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["create_status"], 201, "create_status")
        :ok
      end),
      run_test("CRUD: missing required field", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"title" => "No body"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "POST+GET creates resource",
        input: %{"title" => "Stress Post", "body" => "Testing flow HTTP CRUD", "userId" => 1},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["create_status"] == 201 and
               is_present(output["created_id"]) do
            :ok
          else
            {:error, "expected create_status=201 with created_id, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing title",
        input: %{"body" => "no title here", "userId" => 1},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end

  defp is_present(nil), do: false
  defp is_present(""), do: false
  defp is_present(_), do: true
end
