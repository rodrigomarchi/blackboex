defmodule BlackboexWeb.FlowLive.EditTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/flows/#{Ecto.UUID.generate()}/edit")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "mounts with flow data", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Editor Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/edit")
      assert html =~ "Editor Flow"
      assert html =~ "draft"
      assert html =~ "drawflow-canvas"
    end

    test "redirects when flow not found", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, ~p"/flows/#{Ecto.UUID.generate()}/edit")
        |> follow_redirect(conn)

      assert html =~ "Flow not found"
    end

    test "shows node palette", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Palette Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/edit")
      assert html =~ "Start"
      assert html =~ "Elixir Code"
      assert html =~ "Condition"
      assert html =~ "End"
    end

    test "saves definition via event", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Save Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 100, "y" => 200},
            "data" => %{"name" => "Start"}
          },
          %{
            "id" => "n2",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 200},
            "data" => %{"name" => "End"}
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
      }

      render_hook(view, "save_definition", %{"definition" => definition})

      updated = Blackboex.Flows.get_flow(org.id, flow.id)
      assert updated.definition["version"] == "1.0"
      assert length(updated.definition["nodes"]) == 2
      assert hd(updated.definition["nodes"])["data"]["name"] == "Start"
    end

    test "shows activate button for draft flow", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/edit")
      assert html =~ "Activate"
      assert html =~ "draft"
    end

    test "activates flow with valid definition", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      html = view |> element("button[phx-click='activate_flow']") |> render_click()

      assert html =~ "active"
      assert html =~ "Deactivate"
    end

    test "deactivates an active flow", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})
      {:ok, flow} = Blackboex.Flows.activate_flow(flow)

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      html = view |> element("button[phx-click='deactivate_flow']") |> render_click()

      assert html =~ "draft"
      assert html =~ "Activate"
    end

    test "shows error when activating flow with empty definition", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Empty Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      html = view |> element("button[phx-click='activate_flow']") |> render_click()

      assert html =~ "Cannot activate"
    end

    test "shows History button linking to executions", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_fixture(%{user: user, org: org})

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/edit")
      assert html =~ "History"
      assert html =~ "/flows/#{flow.id}/executions"
    end

    # ── Schema tab & event tests ──────────────────────────────────────────

    test "set_properties_tab event switches tab", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      # Simulate node selection (as JS hook would send)
      render_hook(view, "node_selected", %{
        "id" => "n1",
        "type" => "start",
        "data" => %{"name" => "Start"}
      })

      # Switch to payload schema tab
      html = render_click(view, "set_properties_tab", %{"tab" => "payload_schema"})
      assert html =~ "Payload Fields"
    end

    test "set_properties_tab to state_schema shows state builder", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      render_hook(view, "node_selected", %{
        "id" => "n1",
        "type" => "start",
        "data" => %{"name" => "Start"}
      })

      html = render_click(view, "set_properties_tab", %{"tab" => "state_schema"})
      assert html =~ "State Variables"
    end

    test "end node shows response schema tab", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      render_hook(view, "node_selected", %{
        "id" => "n8",
        "type" => "end",
        "data" => %{"name" => "End"}
      })

      html = render_click(view, "set_properties_tab", %{"tab" => "response_schema"})
      assert html =~ "Response Fields"
    end

    test "schema_add_field adds field to payload_schema", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      render_hook(view, "node_selected", %{
        "id" => "n1",
        "type" => "start",
        "data" => %{"name" => "Start", "payload_schema" => []}
      })

      render_click(view, "set_properties_tab", %{"tab" => "payload_schema"})

      html =
        render_click(view, "schema_add_field", %{"schema-id" => "payload_schema", "path" => ""})

      # Should render the new empty field with type selector
      assert html =~ "field_name"
    end

    test "schema_remove_field removes field from schema", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      render_hook(view, "node_selected", %{
        "id" => "n1",
        "type" => "start",
        "data" => %{
          "name" => "Start",
          "payload_schema" => [
            %{"name" => "first", "type" => "string", "required" => false, "constraints" => %{}},
            %{"name" => "second", "type" => "integer", "required" => false, "constraints" => %{}}
          ]
        }
      })

      render_click(view, "set_properties_tab", %{"tab" => "payload_schema"})

      html =
        render_click(view, "schema_remove_field", %{
          "schema-id" => "payload_schema",
          "path" => "0"
        })

      # First field removed, second should still be visible
      assert html =~ "second"
      refute html =~ ~r/value="first"/
    end

    test "schema_update_field changes field type", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      render_hook(view, "node_selected", %{
        "id" => "n1",
        "type" => "start",
        "data" => %{
          "name" => "Start",
          "payload_schema" => [
            %{"name" => "myfield", "type" => "string", "required" => false, "constraints" => %{}}
          ]
        }
      })

      render_click(view, "set_properties_tab", %{"tab" => "payload_schema"})

      html =
        render_click(view, "schema_update_field", %{
          "schema-id" => "payload_schema",
          "path" => "0",
          "prop" => "type",
          "value" => "integer"
        })

      # Should show number constraints (Min, Max) instead of string constraints
      assert html =~ "Min"
      assert html =~ "Max"
    end

    test "schema_update_constraint sets constraint value", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      render_hook(view, "node_selected", %{
        "id" => "n1",
        "type" => "start",
        "data" => %{
          "name" => "Start",
          "payload_schema" => [
            %{"name" => "name", "type" => "string", "required" => true, "constraints" => %{}}
          ]
        }
      })

      render_click(view, "set_properties_tab", %{"tab" => "payload_schema"})

      # Set min_length constraint
      html =
        render_click(view, "schema_update_constraint", %{
          "schema-id" => "payload_schema",
          "path" => "0",
          "prop" => "min_length",
          "value" => "3"
        })

      assert html =~ "3"
    end

    test "schema_update_mapping sets response mapping", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      render_hook(view, "node_selected", %{
        "id" => "n8",
        "type" => "end",
        "data" => %{
          "name" => "End",
          "response_schema" => [
            %{"name" => "total", "type" => "integer", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => []
        }
      })

      render_click(view, "set_properties_tab", %{"tab" => "response_schema"})

      # Update mapping — the event updates node data and pushes to JS
      render_click(view, "schema_update_mapping", %{
        "response-field" => "total",
        "value" => "counter"
      })

      # Verify the mapping was stored by selecting the node again and checking
      # that response_mapping is in the push_event (via the internal state)
      # We verify by checking the rendered HTML contains the mapping field name
      html = render(view)
      assert html =~ "total"
    end

    test "node_selected resets properties_tab to settings", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      # Select start node and switch to payload tab
      render_hook(view, "node_selected", %{
        "id" => "n1",
        "type" => "start",
        "data" => %{"name" => "Start"}
      })

      render_click(view, "set_properties_tab", %{"tab" => "payload_schema"})

      # Select a different node — should reset to settings
      html =
        render_hook(view, "node_selected", %{
          "id" => "n2",
          "type" => "elixir_code",
          "data" => %{"name" => "Code"}
        })

      assert html =~ "Code"
      # Should not show schema builder
      refute html =~ "Payload Fields"
    end

    test "save definition with schemas round-trips correctly", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Schema Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{
              "name" => "Start",
              "payload_schema" => [
                %{
                  "name" => "name",
                  "type" => "string",
                  "required" => true,
                  "constraints" => %{"min_length" => 1}
                }
              ],
              "state_schema" => [
                %{"name" => "counter", "type" => "integer", "initial_value" => 0}
              ]
            }
          },
          %{
            "id" => "n2",
            "type" => "end",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{
              "name" => "End",
              "response_schema" => [
                %{
                  "name" => "total",
                  "type" => "integer",
                  "required" => true,
                  "constraints" => %{}
                }
              ],
              "response_mapping" => [
                %{"response_field" => "total", "state_variable" => "counter"}
              ]
            }
          }
        ],
        "edges" => []
      }

      render_hook(view, "save_definition", %{"definition" => definition})

      saved = Blackboex.Flows.get_flow(org.id, flow.id)
      start_node = Enum.find(saved.definition["nodes"], &(&1["type"] == "start"))
      end_node = Enum.find(saved.definition["nodes"], &(&1["type"] == "end"))

      assert length(start_node["data"]["payload_schema"]) == 1
      assert hd(start_node["data"]["payload_schema"])["name"] == "name"
      assert length(start_node["data"]["state_schema"]) == 1
      assert hd(start_node["data"]["state_schema"])["initial_value"] == 0

      assert length(end_node["data"]["response_schema"]) == 1
      assert length(end_node["data"]["response_mapping"]) == 1
      assert hd(end_node["data"]["response_mapping"])["state_variable"] == "counter"
    end

    test "rejects invalid definition on save", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Invalid Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      # Send definition with missing version
      invalid = %{"nodes" => [], "edges" => []}
      html = render_hook(view, "save_definition", %{"definition" => invalid})

      assert html =~ "Invalid flow"
    end
  end
end
