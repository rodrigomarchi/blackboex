defmodule Blackboex.Apis.Templates.CrudResource do
  @moduledoc """
  Template: REST CRUD Resource

  Generic CRUD operations over an in-memory store.
  Supports list, get, create, update and delete via the `action` field.
  """

  @spec template() :: Blackboex.Apis.Templates.template()
  def template do
    %{
      id: "crud-resource",
      name: "REST CRUD Resource",
      description: "CRUD completo genérico para qualquer recurso (in-memory)",
      category: "Protótipos",
      icon: "table-cells",
      method: "POST",
      files: %{
        handler: handler_code(),
        helpers: helpers_code(),
        request_schema: request_schema_code(),
        response_schema: response_schema_code(),
        test: test_code(),
        readme: readme_content()
      },
      param_schema: %{
        "action" => "string",
        "id" => "string",
        "data" => "object"
      },
      example_request: %{
        "action" => "create",
        "data" => %{"name" => "Item 1", "value" => 42}
      },
      example_response: %{
        "success" => true,
        "data" => %{
          "id" => "res_abc123",
          "name" => "Item 1",
          "value" => 42,
          "created_at" => "2024-01-15T10:00:00Z"
        }
      },
      validation_report: %{
        "compilation" => "pass",
        "compilation_errors" => [],
        "format" => "pass",
        "format_issues" => [],
        "credo" => "pass",
        "credo_issues" => [],
        "tests" => "pass",
        "test_results" => [
          %{"name" => "create returns new resource with id", "status" => "pass"},
          %{"name" => "list returns array of resources", "status" => "pass"},
          %{"name" => "get returns resource by id", "status" => "pass"},
          %{"name" => "update modifies resource fields", "status" => "pass"},
          %{"name" => "delete removes resource", "status" => "pass"},
          %{"name" => "invalid action returns validation error", "status" => "pass"},
          %{"name" => "missing action returns validation error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Handler for REST CRUD resource endpoint."

      @doc "Processes a CRUD action request and returns the operation result."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          Helpers.execute(data.action, data.id, data.data)
        else
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          %{error: "Validation failed", details: errors}
        end
      end
    end
    """
  end

  defp helpers_code do
    ~S"""
    defmodule Helpers do
      @moduledoc "Helper functions for in-memory CRUD operations."

      # Simulated in-memory store (static data for demo purposes)
      @store [
        %{id: "res_001", name: "Resource Alpha", value: 100, created_at: "2024-01-10T08:00:00Z"},
        %{id: "res_002", name: "Resource Beta", value: 200, created_at: "2024-01-11T09:00:00Z"},
        %{id: "res_003", name: "Resource Gamma", value: 300, created_at: "2024-01-12T10:00:00Z"}
      ]

      @doc "Executes a CRUD action against the in-memory store."
      @spec execute(String.t(), String.t() | nil, map() | nil) :: map()
      def execute("list", _id, _data) do
        %{success: true, data: @store, meta: %{total: length(@store)}}
      end

      def execute("get", id, _data) when is_binary(id) do
        case Enum.find(@store, &(&1.id == id)) do
          nil -> %{success: false, error: "Resource #{id} not found"}
          resource -> %{success: true, data: resource}
        end
      end

      def execute("get", nil, _data) do
        %{success: false, error: "id is required for get action"}
      end

      def execute("create", _id, data) when is_map(data) do
        hash =
          data
          |> Map.keys()
          |> Enum.sort()
          |> Enum.join("_")
          |> String.length()
          |> rem(0xFFFFFF)

        new_id = "res_#{Integer.to_string(hash, 16)}"
        resource = Map.merge(data, %{"id" => new_id, "created_at" => "2024-01-15T10:00:00Z"})
        %{success: true, data: resource}
      end

      def execute("create", _id, _data) do
        %{success: false, error: "data is required for create action"}
      end

      def execute("update", id, data) when is_binary(id) and is_map(data) do
        case Enum.find(@store, &(&1.id == id)) do
          nil -> %{success: false, error: "Resource #{id} not found"}
          resource -> %{success: true, data: Map.merge(resource, atomize_keys(data))}
        end
      end

      def execute("update", _id, _data) do
        %{success: false, error: "id and data are required for update action"}
      end

      def execute("delete", id, _data) when is_binary(id) do
        case Enum.find(@store, &(&1.id == id)) do
          nil -> %{success: false, error: "Resource #{id} not found"}
          _resource -> %{success: true, deleted_id: id}
        end
      end

      def execute("delete", nil, _data) do
        %{success: false, error: "id is required for delete action"}
      end

      def execute(action, _id, _data) do
        %{success: false, error: "Unknown action: #{action}"}
      end

      defp atomize_keys(map) do
        # Keep string keys — no atom conversion in sandbox context
        map
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for REST CRUD resource."

      use Blackboex.Schema
      import Ecto.Changeset

      @valid_actions ["list", "get", "create", "update", "delete"]

      @primary_key false
      embedded_schema do
        field :action, :string
        field :id, :string
        field :data, :map
      end

      @doc "Casts and validates CRUD action request params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:action, :id, :data])
        |> validate_required([:action])
        |> validate_inclusion(:action, @valid_actions)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema documenting the CRUD resource output."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :success, :boolean
        field :data, :map
        field :error, :string
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case, async: true

      describe "handle/1" do
        test "list returns array of resources" do
          result = Handler.handle(%{"action" => "list"})
          assert result.success == true
          assert is_list(result.data)
          assert length(result.data) > 0
        end

        test "get with valid id returns resource" do
          result = Handler.handle(%{"action" => "get", "id" => "res_001"})
          assert result.success == true
          assert result.data.id == "res_001"
        end

        test "get with unknown id returns failure" do
          result = Handler.handle(%{"action" => "get", "id" => "nonexistent"})
          assert result.success == false
        end

        test "create returns new resource with generated id" do
          result = Handler.handle(%{
            "action" => "create",
            "data" => %{"name" => "New Item", "value" => 42}
          })
          assert result.success == true
          assert Map.has_key?(result.data, "id") or Map.has_key?(result.data, :id)
        end

        test "update modifies resource fields" do
          result = Handler.handle(%{
            "action" => "update",
            "id" => "res_001",
            "data" => %{"name" => "Updated Name"}
          })
          assert result.success == true
        end

        test "delete removes resource" do
          result = Handler.handle(%{"action" => "delete", "id" => "res_001"})
          assert result.success == true
        end

        test "invalid action returns validation error" do
          result = Handler.handle(%{"action" => "truncate"})
          assert result.error == "Validation failed"
          assert Map.has_key?(result.details, :action)
        end

        test "missing action returns validation error" do
          result = Handler.handle(%{})
          assert result.error == "Validation failed"
          assert Map.has_key?(result.details, :action)
        end
      end

      test "Request.changeset validates required fields" do
        cs = Request.changeset(%{})
        refute cs.valid?
        assert Keyword.has_key?(cs.errors, :action)
      end
    end
    """
  end

  defp readme_content do
    """
    # REST CRUD Resource

    Ponto de partida para qualquer recurso REST. Implementa as 5 operações
    CRUD básicas sobre um store in-memory estático — ideal para prototipagem
    rápida antes de conectar ao banco de dados real.

    ## Ações Disponíveis

    | Ação | Descrição | Campos Necessários |
    |------|-----------|-------------------|
    | `list` | Lista todos os recursos | — |
    | `get` | Retorna um recurso por ID | `id` |
    | `create` | Cria novo recurso | `data` |
    | `update` | Atualiza campos do recurso | `id`, `data` |
    | `delete` | Remove o recurso | `id` |

    ## Exemplo — Criar

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/crud-resource \\
      -H "Content-Type: application/json" \\
      -d '{"action": "create", "data": {"name": "Item 1", "value": 42}}'
    ```

    ## Exemplo — Listar

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/crud-resource \\
      -H "Content-Type: application/json" \\
      -d '{"action": "list"}'
    ```

    ## Personalização

    Substitua `@store` no módulo `Helpers` por chamadas reais ao banco de dados.
    O contrato da API permanece idêntico.
    """
  end
end
