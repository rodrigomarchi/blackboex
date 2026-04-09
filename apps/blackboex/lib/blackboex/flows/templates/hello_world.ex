defmodule Blackboex.Flows.Templates.HelloWorld do
  @moduledoc """
  Hello World "Contact Router" template.

  A flow that receives name (required), phone (optional), email (optional)
  and routes a greeting message to the appropriate delivery channel.

  Exercises all node types: start, elixir_code (4), condition (3-way), end (3).

  ## Flow graph

      Start → Validate Input → Build Contact Info → Route by Contact (3 outputs)
        → Port 0: Format Email Message → End (Email)
        → Port 1: Format Phone Message → End (Phone)
        → Port 2: No Contact Error    → End (Error)
  """

  @doc "Returns the Hello World flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "hello_world",
      name: "Hello World",
      description: "A contact router that demonstrates validation, branching, and all node types",
      category: "Getting Started",
      icon: "hero-hand-raised",
      definition: definition()
    }
  end

  defp definition do
    %{
      "version" => "1.0",
      "nodes" => nodes(),
      "edges" => edges()
    }
  end

  defp nodes do
    [
      # ── Start ──
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 250},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 30_000
        }
      },

      # ── Validate Input ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 250, "y" => 250},
        "data" => %{
          "name" => "Validate Input",
          "code" => ~S"""
          if is_nil(input["name"]) or input["name"] == "" do
            raise "name is required"
          end

          {input, state}
          """
        }
      },

      # ── Build Contact Info ──
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 450, "y" => 250},
        "data" => %{
          "name" => "Build Contact Info",
          "code" => ~S"""
          name = input["name"]
          greeting = "Hello, #{name}!"

          contact_type =
            cond do
              input["email"] != nil -> "email"
              input["phone"] != nil -> "phone"
              true -> "none"
            end

          new_state = Map.merge(state, %{
            "greeting" => greeting,
            "contact_type" => contact_type,
            "email" => input["email"],
            "phone" => input["phone"]
          })

          {input, new_state}
          """
        }
      },

      # ── Condition: Route by Contact ──
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 650, "y" => 250},
        "data" => %{
          "name" => "Route by Contact",
          "expression" => ~S"""
          cond do
            input["email"] != nil -> 0
            input["phone"] != nil -> 1
            true -> 2
          end
          """,
          "branch_labels" => %{
            "0" => "Has Email",
            "1" => "Has Phone",
            "2" => "No Contact"
          }
        }
      },

      # ── Branch 0: Format Email Message ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 100},
        "data" => %{
          "name" => "Format Email Message",
          "code" => ~S"""
          greeting = state["greeting"]
          email = state["email"]

          result = %{
            "channel" => "email",
            "to" => email,
            "message" => greeting
          }

          {result, Map.put(state, "delivered_via", "email")}
          """
        }
      },

      # ── Branch 1: Format Phone Message ──
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 300},
        "data" => %{
          "name" => "Format Phone Message",
          "code" => ~S"""
          greeting = state["greeting"]
          phone = state["phone"]

          result = %{
            "channel" => "phone",
            "to" => phone,
            "message" => greeting
          }

          {result, Map.put(state, "delivered_via", "phone")}
          """
        }
      },

      # ── Branch 2: No Contact Error ──
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 500},
        "data" => %{
          "name" => "No Contact Error",
          "code" => ~S"""
          result = %{"error" => "no contact info provided"}

          {result, Map.put(state, "delivered_via", "none")}
          """
        }
      },

      # ── End nodes ──
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1150, "y" => 100},
        "data" => %{"name" => "End (Email)"}
      },
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1150, "y" => 300},
        "data" => %{"name" => "End (Phone)"}
      },
      %{
        "id" => "n10",
        "type" => "end",
        "position" => %{"x" => 1150, "y" => 500},
        "data" => %{"name" => "End (Error)"}
      }
    ]
  end

  defp edges do
    [
      # Start → Validate Input
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      # Validate Input → Build Contact Info
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      # Build Contact Info → Route by Contact
      %{"id" => "e3", "source" => "n3", "source_port" => 0, "target" => "n4", "target_port" => 0},
      # Route by Contact → Format Email (port 0)
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      # Route by Contact → Format Phone (port 1)
      %{"id" => "e5", "source" => "n4", "source_port" => 1, "target" => "n6", "target_port" => 0},
      # Route by Contact → No Contact Error (port 2)
      %{"id" => "e6", "source" => "n4", "source_port" => 2, "target" => "n7", "target_port" => 0},
      # Format Email → End (Email)
      %{"id" => "e7", "source" => "n5", "source_port" => 0, "target" => "n8", "target_port" => 0},
      # Format Phone → End (Phone)
      %{"id" => "e8", "source" => "n6", "source_port" => 0, "target" => "n9", "target_port" => 0},
      # No Contact Error → End (Error)
      %{"id" => "e9", "source" => "n7", "source_port" => 0, "target" => "n10", "target_port" => 0}
    ]
  end
end
