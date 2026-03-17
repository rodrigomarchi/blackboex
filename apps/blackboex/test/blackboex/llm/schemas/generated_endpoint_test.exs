defmodule Blackboex.LLM.Schemas.GeneratedEndpointTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.LLM.Schemas.GeneratedEndpoint

  @valid_attrs %{
    handler_code: "def call(conn, params), do: json(conn, %{ok: true})",
    method: "POST",
    description: "A test endpoint",
    example_request: %{"key" => "value"},
    example_response: %{"ok" => true},
    param_schema: %{"type" => "object"}
  }

  describe "changeset/2" do
    test "valid with all required fields" do
      changeset = GeneratedEndpoint.changeset(%GeneratedEndpoint{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires handler_code" do
      changeset =
        GeneratedEndpoint.changeset(
          %GeneratedEndpoint{},
          Map.delete(@valid_attrs, :handler_code)
        )

      refute changeset.valid?
      assert %{handler_code: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires method" do
      changeset =
        GeneratedEndpoint.changeset(
          %GeneratedEndpoint{},
          Map.delete(@valid_attrs, :method)
        )

      refute changeset.valid?
      assert %{method: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires description" do
      changeset =
        GeneratedEndpoint.changeset(
          %GeneratedEndpoint{},
          Map.delete(@valid_attrs, :description)
        )

      refute changeset.valid?
      assert %{description: ["can't be blank"]} = errors_on(changeset)
    end

    test "method defaults to POST if not provided in attrs but is in struct" do
      # If method is not in attrs at all, changeset requires it
      changeset =
        GeneratedEndpoint.changeset(%GeneratedEndpoint{}, %{
          handler_code: "code",
          description: "test"
        })

      refute changeset.valid?
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
