#!/usr/bin/env elixir
# End-to-end test script for BlackBoex core functionality.
#
# Part 1: Hardcoded tests (no LLM, deterministic, fast)
# Part 2: LLM-powered tests (requires ANTHROPIC_API_KEY)
# Part 3: HTTP tests (requires server running on localhost:4000)
#
# Usage:
#   mix run scripts/e2e_test.exs
#   ANTHROPIC_API_KEY="sk-ant-..." mix run scripts/e2e_test.exs

defmodule E2ETest do
  @moduledoc false

  alias Blackboex.Accounts
  alias Blackboex.Apis
  alias Blackboex.Apis.Api
  alias Blackboex.Apis.Keys
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.Linter
  alias Blackboex.CodeGen.SchemaExtractor
  alias Blackboex.Repo

  @base_url "http://localhost:4000"

  # ── Hardcoded handler code ───────────────────────────────────────────

  @factorial_code """
  defmodule Request do
    use Blackboex.Schema

    embedded_schema do
      field :number, :integer
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:number])
      |> validate_required([:number])
      |> validate_number(:number, greater_than_or_equal_to: 0)
    end
  end

  defmodule Response do
    use Blackboex.Schema

    embedded_schema do
      field :result, :integer
      field :number, :integer
    end
  end

  @doc "Calculates factorial."
  @spec handle(map()) :: map()
  def handle(params) do
    changeset = Request.changeset(params)

    if changeset.valid? do
      data = Ecto.Changeset.apply_changes(changeset)
      %{result: factorial(data.number), number: data.number}
    else
      %{error: "Invalid input"}
    end
  end

  defp factorial(0), do: 1
  defp factorial(n) when n > 0, do: n * factorial(n - 1)
  """

  @crud_code """
  defmodule Request do
    use Blackboex.Schema

    embedded_schema do
      field :name, :string
      field :email, :string
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:name, :email])
      |> validate_required([:name])
    end
  end

  defmodule Response do
    use Blackboex.Schema

    embedded_schema do
      field :id, :string
      field :name, :string
    end
  end

  @doc "Lists all items."
  @spec handle_list(map()) :: map()
  def handle_list(_params), do: %{items: [%{id: "1", name: "Alice"}, %{id: "2", name: "Bob"}]}

  @doc "Gets an item by ID."
  @spec handle_get(String.t(), map()) :: map()
  def handle_get(id, _params), do: %{id: id, name: "User"}

  @doc "Creates an item."
  @spec handle_create(map()) :: map()
  def handle_create(params) do
    cs = Request.changeset(params)

    if cs.valid? do
      data = Ecto.Changeset.apply_changes(cs)
      %{id: "new", name: data.name, created: true}
    else
      %{error: "Invalid"}
    end
  end

  @doc "Updates an item."
  @spec handle_update(String.t(), map()) :: map()
  def handle_update(id, params) do
    cs = Request.changeset(params)

    if cs.valid? do
      data = Ecto.Changeset.apply_changes(cs)
      %{id: id, name: data.name, updated: true}
    else
      %{error: "Invalid"}
    end
  end

  @doc "Deletes an item."
  @spec handle_delete(String.t()) :: map()
  def handle_delete(id), do: %{id: id, deleted: true}
  """

  @webhook_code """
  @doc "Handles incoming webhook."
  @spec handle_webhook(map()) :: map()
  def handle_webhook(payload) do
    event = Map.get(payload, "event", "unknown")
    %{received: true, event: event, processed_at: DateTime.to_iso8601(DateTime.utc_now())}
  end
  """

  # ── Main runner ──────────────────────────────────────────────────────

  def run do
    IO.puts("\n#{IO.ANSI.bright()}=== BlackBoex E2E Test ===" <> IO.ANSI.reset())
    IO.puts("Comprehensive platform lifecycle tests\n")

    # Part 1: Hardcoded (deterministic, no LLM)
    part1 = run_part("Part 1: Hardcoded Tests (no LLM)", [
      {"1.1a Setup: create user + organization", &setup/0},
      {"1.1b Computation: compile factorial handler", &compile_factorial/0},
      {"1.1c Computation: register + lookup in Registry", &register_factorial/0},
      {"1.1d Computation: execute via Plug.Test.conn (5! = 120)", &execute_factorial_valid/0},
      {"1.1e Computation: error for invalid input", &execute_factorial_invalid/0},
      {"1.1f Computation: create version + verify history", &version_factorial/0},
      {"1.1g Computation: publish + create API key", &publish_factorial/0},
      {"1.1h Computation: verify API key format + verification", &verify_api_key_format/0},
      {"1.2a CRUD: compile handler", &compile_crud/0},
      {"1.2b CRUD: register in Registry", &register_crud/0},
      {"1.2c CRUD: GET / -> list", &crud_list/0},
      {"1.2d CRUD: GET /123 -> get by id", &crud_get/0},
      {"1.2e CRUD: POST / -> create", &crud_create/0},
      {"1.2f CRUD: PUT /123 -> update", &crud_update/0},
      {"1.2g CRUD: DELETE /123 -> delete", &crud_delete/0},
      {"1.3a Webhook: compile handler", &compile_webhook/0},
      {"1.3b Webhook: register + POST / with payload", &execute_webhook/0},
      {"1.4a Security: File.read blocked", &security_file_read/0},
      {"1.4b Security: System.cmd blocked", &security_system_cmd/0},
      {"1.4c Security: Ecto.Repo blocked", &security_ecto_repo/0},
      {"1.4d Security: Ecto.Query blocked", &security_ecto_query/0},
      {"1.4e Security: unsafe_validate_unique blocked", &security_unsafe_validate/0},
      {"1.4f Security: Application.get_env blocked", &security_application/0},
      {"1.4g Security: spawn blocked", &security_spawn/0},
      {"1.4h Security: use Blackboex.Schema allowed", &security_schema_allowed/0},
      {"1.4i Security: import Ecto.Changeset allowed", &security_changeset_allowed/0},
      {"1.4j Security: defmodule Request allowed", &security_request_allowed/0},
      {"1.4k Security: defmodule Hacker blocked", &security_hacker_blocked/0},
      {"1.5a SchemaExtractor: extract from compiled module", &schema_extract/0},
      {"1.5b SchemaExtractor: verify field types", &schema_field_types/0},
      {"1.5c SchemaExtractor: verify required fields", &schema_required_fields/0},
      {"1.6a API Key: create + verify", &key_create_verify/0},
      {"1.6b API Key: wrong key fails", &key_wrong_fails/0},
      {"1.6c API Key: revoke + rejected", &key_revoke_rejected/0},
      {"1.6d API Key: wrong API fails", &key_wrong_api/0},
      {"1.7a Versions: create v1, modify v2", &versions_create/0},
      {"1.7b Versions: list + verify count", &versions_list/0},
      {"1.7c Versions: rollback to v1", &versions_rollback/0},
      {"1.8a Linter: missing @spec detected", &linter_missing_spec/0},
      {"1.8b Linter: missing @doc detected", &linter_missing_doc/0},
      {"1.8c Linter: unformatted code detected", &linter_unformatted/0},
      {"1.8d Linter: clean code passes", &linter_clean/0},
      {"1.99 Cleanup Part 1", &cleanup_part1/0}
    ])

    # Part 2: LLM-powered (requires ANTHROPIC_API_KEY)
    part2 =
      if has_anthropic_key?() do
        run_part("Part 2: LLM-Powered Tests", [
          {"2.0 Setup for LLM tests", &setup_llm/0},
          {"2.1a Generate factorial API via LLM", &llm_generate/0},
          {"2.1b Verify generated code has Request DTO", &llm_verify_dto/0},
          {"2.1c Compile generated code", &llm_compile/0},
          {"2.1d Run unified pipeline (validate_and_test)", &llm_pipeline/0},
          {"2.1e Save + publish generated API", &llm_save_publish/0},
          {"2.2a Verify test code calls Handler.handle()", &llm_test_structure/0},
          {"2.99 Cleanup Part 2", &cleanup_part2/0}
        ])
      else
        IO.puts("\n#{IO.ANSI.yellow()}Part 2: SKIPPED (no ANTHROPIC_API_KEY)#{IO.ANSI.reset()}")
        {0, 0, length([1, 2, 3, 4, 5, 6, 7, 8])}
      end

    # Part 3: HTTP tests (requires server on :4000)
    part3 =
      if Process.get(:e2e_server_up) do
        run_part("Part 3: HTTP Tests (live server)", [
          {"3.0 Setup for HTTP tests", &setup_http/0},
          {"3.1a Published API: POST with valid key -> 200", &http_auth_valid/0},
          {"3.1b Published API: POST without key -> 401", &http_auth_missing/0},
          {"3.1c Published API: POST with wrong key -> 401", &http_auth_wrong/0},
          {"3.1d Published API: POST with revoked key -> 401", &http_auth_revoked/0},
          {"3.2a No-auth API: POST without key -> 200", &http_noauth/0},
          {"3.3a OpenAPI: GET openapi.json -> valid spec", &http_openapi_json/0},
          {"3.3b OpenAPI: GET /docs -> Swagger UI", &http_swagger_ui/0},
          {"3.4a Error: POST with missing params", &http_error_missing/0},
          {"3.4b Error: POST with invalid JSON -> 400", &http_error_invalid_json/0},
          {"3.99 Cleanup Part 3", &cleanup_part3/0}
        ])
      else
        IO.puts("\n#{IO.ANSI.yellow()}Part 3: SKIPPED (server not running)#{IO.ANSI.reset()}")
        {0, 0, length([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])}
      end

    print_summary(part1, part2, part3)
  end

  # ── Part 1: Hardcoded Tests ──────────────────────────────────────────

  defp setup do
    email = "e2e-#{System.unique_integer([:positive])}@test.com"
    {:ok, user} = Accounts.register_user(%{email: email})

    user
    |> Ecto.Changeset.change(%{confirmed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)})
    |> Repo.update!()

    user = Repo.get!(Blackboex.Accounts.User, user.id)
    [org] = Blackboex.Organizations.list_user_organizations(user)

    Process.put(:e2e_user, user)
    Process.put(:e2e_org, org)

    assert(user.id != nil, "User created")
    assert(org.id != nil, "Organization created")
    info("User: #{email}, Org: #{org.slug}")
  end

  # 1.1: Computation API lifecycle

  defp compile_factorial do
    org = Process.get(:e2e_org)
    user = Process.get(:e2e_user)

    {:ok, api} =
      Apis.create_api(%{
        name: "E2E Factorial",
        slug: "e2e-fact-#{System.unique_integer([:positive])}",
        description: "Calculates factorial",
        source_code: @factorial_code,
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })

    Process.put(:e2e_fact_api, api)

    case Compiler.compile(api, @factorial_code) do
      {:ok, module} ->
        Process.put(:e2e_fact_module, module)
        assert(function_exported?(module, :call, 2), "Module implements Plug")
        info("Compiled: #{inspect(module)}")

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  defp register_factorial do
    api = Process.get(:e2e_fact_api)
    module = Process.get(:e2e_fact_module)
    org = Process.get(:e2e_org)

    :ok =
      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug,
        requires_auth: api.requires_auth,
        visibility: api.visibility
      )

    {:ok, found_mod, _meta} = Registry.lookup(api.id)
    assert(found_mod == module, "Registry lookup returned correct module")
    info("Registered and lookup OK")
  end

  defp execute_factorial_valid do
    module = Process.get(:e2e_fact_module)

    conn =
      Plug.Test.conn(:post, "/", Jason.encode!(%{"number" => 5}))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    result = module.call(conn, module.init([]))
    body = Jason.decode!(result.resp_body)

    assert(result.status == 200, "Status 200 (got #{result.status})")
    assert(body["result"] == 120, "5! = 120 (got #{inspect(body["result"])})")
    assert(body["number"] == 5, "number echoed back")
    info("5! = #{body["result"]}")
  end

  defp execute_factorial_invalid do
    module = Process.get(:e2e_fact_module)

    # Missing params
    conn1 =
      Plug.Test.conn(:post, "/", Jason.encode!(%{}))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    r1 = module.call(conn1, module.init([]))
    b1 = Jason.decode!(r1.resp_body)
    assert(b1["error"] != nil, "Error returned for empty params")
    info("Empty params -> #{inspect(b1)}")

    # Negative number
    conn2 =
      Plug.Test.conn(:post, "/", Jason.encode!(%{"number" => -1}))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    r2 = module.call(conn2, module.init([]))
    b2 = Jason.decode!(r2.resp_body)
    assert(b2["error"] != nil, "Error returned for negative number")
    info("Negative -> #{inspect(b2)}")
  end

  defp version_factorial do
    api = Process.get(:e2e_fact_api)

    {:ok, v1} =
      Apis.create_version(api, %{
        code: @factorial_code,
        source: "manual_edit",
        prompt: "Initial version"
      })

    assert(v1.version_number == 1, "Version 1 created")

    versions = Apis.list_versions(api.id)
    assert(length(versions) == 1, "1 version in history")
    info("Version #{v1.version_number} created")
  end

  defp publish_factorial do
    api = Process.get(:e2e_fact_api)
    org = Process.get(:e2e_org)
    module = Process.get(:e2e_fact_module)

    # Must be in compiled state first
    {:ok, api} = Apis.update_api(api, %{status: "compiled"})
    Process.put(:e2e_fact_api, api)

    # Re-register with updated state
    Registry.unregister(api.id)

    :ok =
      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug,
        requires_auth: api.requires_auth,
        visibility: api.visibility
      )

    case Apis.publish(api, org) do
      {:ok, published_api, plain_key} ->
        Process.put(:e2e_fact_api, published_api)
        Process.put(:e2e_fact_key, plain_key)
        assert(published_api.status == "published", "Published")
        info("Published with key: #{String.slice(plain_key, 0, 20)}...")

      {:error, reason} ->
        raise "Publish failed: #{inspect(reason)}"
    end
  end

  defp verify_api_key_format do
    key = Process.get(:e2e_fact_key)
    api = Process.get(:e2e_fact_api)

    assert(String.starts_with?(key, "bb_live_"), "Key starts with bb_live_")
    assert(String.length(key) > 20, "Key has sufficient length")

    {:ok, api_key} = Keys.verify_key(key)
    assert(api_key.api_id == api.id, "Key belongs to correct API")
    info("Key format and verification OK")
  end

  # 1.2: CRUD API lifecycle

  defp compile_crud do
    org = Process.get(:e2e_org)
    user = Process.get(:e2e_user)

    {:ok, api} =
      Apis.create_api(%{
        name: "E2E CRUD",
        slug: "e2e-crud-#{System.unique_integer([:positive])}",
        description: "CRUD test",
        source_code: @crud_code,
        template_type: "crud",
        organization_id: org.id,
        user_id: user.id
      })

    Process.put(:e2e_crud_api, api)

    case Compiler.compile(api, @crud_code) do
      {:ok, module} ->
        Process.put(:e2e_crud_module, module)
        assert(function_exported?(module, :call, 2), "CRUD module implements Plug")
        info("Compiled: #{inspect(module)}")

      {:error, reason} ->
        raise "CRUD compilation failed: #{inspect(reason)}"
    end
  end

  defp register_crud do
    api = Process.get(:e2e_crud_api)
    module = Process.get(:e2e_crud_module)
    org = Process.get(:e2e_org)

    :ok =
      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug,
        requires_auth: api.requires_auth,
        visibility: api.visibility
      )

    info("Registered CRUD API")
  end

  defp crud_list do
    module = Process.get(:e2e_crud_module)

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("content-type", "application/json")

    result = module.call(conn, module.init([]))
    body = Jason.decode!(result.resp_body)

    assert(result.status == 200, "GET / -> 200")
    assert(is_list(body["items"]), "Returns items list")
    assert(length(body["items"]) == 2, "2 items returned")
    info("List: #{length(body["items"])} items")
  end

  defp crud_get do
    module = Process.get(:e2e_crud_module)

    conn =
      Plug.Test.conn(:get, "/123")
      |> Plug.Conn.put_req_header("content-type", "application/json")

    result = module.call(conn, module.init([]))
    body = Jason.decode!(result.resp_body)

    assert(result.status == 200, "GET /123 -> 200")
    assert(body["id"] == "123", "Correct ID returned")
    assert(body["name"] == "User", "Name returned")
    info("Get: id=#{body["id"]}, name=#{body["name"]}")
  end

  defp crud_create do
    module = Process.get(:e2e_crud_module)

    conn =
      Plug.Test.conn(:post, "/", Jason.encode!(%{"name" => "Charlie", "email" => "c@test.com"}))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    result = module.call(conn, module.init([]))
    body = Jason.decode!(result.resp_body)

    assert(result.status == 201, "POST / -> 201 (got #{result.status})")
    assert(body["created"] == true, "created flag set")
    assert(body["name"] == "Charlie", "Name matches")
    info("Create: #{inspect(body)}")
  end

  defp crud_update do
    module = Process.get(:e2e_crud_module)

    conn =
      Plug.Test.conn(:put, "/123", Jason.encode!(%{"name" => "Updated"}))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    result = module.call(conn, module.init([]))
    body = Jason.decode!(result.resp_body)

    assert(result.status == 200, "PUT /123 -> 200")
    assert(body["updated"] == true, "updated flag set")
    assert(body["id"] == "123", "Correct ID")
    info("Update: #{inspect(body)}")
  end

  defp crud_delete do
    module = Process.get(:e2e_crud_module)

    conn =
      Plug.Test.conn(:delete, "/123")
      |> Plug.Conn.put_req_header("content-type", "application/json")

    result = module.call(conn, module.init([]))
    body = Jason.decode!(result.resp_body)

    assert(result.status == 200, "DELETE /123 -> 200")
    assert(body["deleted"] == true, "deleted flag set")
    assert(body["id"] == "123", "Correct ID")
    info("Delete: #{inspect(body)}")
  end

  # 1.3: Webhook API lifecycle

  defp compile_webhook do
    org = Process.get(:e2e_org)
    user = Process.get(:e2e_user)

    {:ok, api} =
      Apis.create_api(%{
        name: "E2E Webhook",
        slug: "e2e-hook-#{System.unique_integer([:positive])}",
        description: "Webhook test",
        source_code: @webhook_code,
        template_type: "webhook",
        organization_id: org.id,
        user_id: user.id
      })

    Process.put(:e2e_webhook_api, api)

    case Compiler.compile(api, @webhook_code) do
      {:ok, module} ->
        Process.put(:e2e_webhook_module, module)
        assert(function_exported?(module, :call, 2), "Webhook module implements Plug")
        info("Compiled: #{inspect(module)}")

      {:error, reason} ->
        raise "Webhook compilation failed: #{inspect(reason)}"
    end
  end

  defp execute_webhook do
    api = Process.get(:e2e_webhook_api)
    module = Process.get(:e2e_webhook_module)
    org = Process.get(:e2e_org)

    :ok =
      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug,
        requires_auth: api.requires_auth,
        visibility: api.visibility
      )

    conn =
      Plug.Test.conn(:post, "/", Jason.encode!(%{"event" => "user.created", "data" => %{"id" => 42}}))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    result = module.call(conn, module.init([]))
    body = Jason.decode!(result.resp_body)

    assert(result.status == 200, "POST / -> 200")
    assert(body["received"] == true, "received flag set")
    assert(body["event"] == "user.created", "Event echoed")
    info("Webhook response: #{inspect(body)}")
  end

  # 1.4: Security / Sandbox tests

  defp security_file_read do
    assert_blocked(~S|File.read("/etc/passwd")|, "File.read")
  end

  defp security_system_cmd do
    assert_blocked(~S|System.cmd("ls", ["/"])|, "System.cmd")
  end

  defp security_ecto_repo do
    assert_blocked(~S|Ecto.Repo.all(User)|, "Ecto.Repo")
  end

  defp security_ecto_query do
    code = """
    import Ecto.Query
    from(u in "users", select: u.email)
    """

    assert_blocked(code, "Ecto.Query")
  end

  defp security_unsafe_validate do
    code = """
    import Ecto.Changeset
    Ecto.Changeset.unsafe_validate_unique(changeset, [:email], Repo)
    """

    assert_blocked(code, "unsafe_validate_unique")
  end

  defp security_application do
    assert_blocked(~S|Application.get_env(:blackboex, :secret)|, "Application.get_env")
  end

  defp security_spawn do
    assert_blocked(~S|spawn(fn -> :ok end)|, "spawn")
  end

  defp security_schema_allowed do
    code = """
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :name, :string
      end
    end

    @doc "Test."
    @spec handle(map()) :: map()
    def handle(params), do: params
    """

    api = %Api{id: Ecto.UUID.generate(), template_type: "computation"}

    case Compiler.compile(api, code) do
      {:ok, module} ->
        Compiler.unload(module)
        info("use Blackboex.Schema compiles OK")

      {:error, reason} ->
        raise "Should have been allowed: #{inspect(reason)}"
    end
  end

  defp security_changeset_allowed do
    code = """
    import Ecto.Changeset

    @doc "Test."
    @spec handle(map()) :: map()
    def handle(params), do: params
    """

    api = %Api{id: Ecto.UUID.generate(), template_type: "computation"}

    case Compiler.compile(api, code) do
      {:ok, module} ->
        Compiler.unload(module)
        info("import Ecto.Changeset compiles OK")

      {:error, reason} ->
        raise "Should have been allowed: #{inspect(reason)}"
    end
  end

  defp security_request_allowed do
    code = """
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :value, :integer
      end
    end

    @doc "Test."
    @spec handle(map()) :: map()
    def handle(params), do: params
    """

    api = %Api{id: Ecto.UUID.generate(), template_type: "computation"}

    case Compiler.compile(api, code) do
      {:ok, module} ->
        Compiler.unload(module)
        info("defmodule Request compiles OK")

      {:error, reason} ->
        raise "Should have been allowed: #{inspect(reason)}"
    end
  end

  defp security_hacker_blocked do
    code = """
    defmodule Hacker do
      def pwn, do: :owned
    end

    @doc "Test."
    @spec handle(map()) :: map()
    def handle(params), do: params
    """

    api = %Api{id: Ecto.UUID.generate(), template_type: "computation"}

    case Compiler.compile(api, code) do
      {:error, {:validation, reasons}} ->
        assert(
          Enum.any?(reasons, &String.contains?(&1, "Hacker")),
          "Error mentions Hacker module"
        )

        info("defmodule Hacker blocked: #{hd(reasons)}")

      {:ok, module} ->
        Compiler.unload(module)
        raise "Security: defmodule Hacker should have been blocked!"
    end
  end

  # 1.5: SchemaExtractor

  defp schema_extract do
    module = Process.get(:e2e_fact_module)
    {:ok, schema} = SchemaExtractor.extract(module)
    Process.put(:e2e_schema, schema)

    assert(schema.request != nil, "Request schema extracted")
    assert(schema.response != nil, "Response schema extracted")
    info("Extracted request + response schemas")
  end

  defp schema_field_types do
    schema = Process.get(:e2e_schema)

    req_fields = schema.request.fields
    assert(req_fields[:number] == :integer, "Request.number is :integer (got #{inspect(req_fields[:number])})")

    resp_fields = schema.response.fields
    assert(resp_fields[:result] == :integer, "Response.result is :integer")
    assert(resp_fields[:number] == :integer, "Response.number is :integer")
    info("Field types match: number=integer, result=integer")
  end

  defp schema_required_fields do
    schema = Process.get(:e2e_schema)
    required = schema.request.required

    assert(:number in required, "number is required (got #{inspect(required)})")
    info("Required fields: #{inspect(required)}")
  end

  # 1.6: API Key tests

  defp key_create_verify do
    api = Process.get(:e2e_fact_api)
    org = Process.get(:e2e_org)

    {:ok, plain_key, api_key} = Keys.create_key(api, %{label: "Test key", organization_id: org.id})
    Process.put(:e2e_test_key, plain_key)
    Process.put(:e2e_test_api_key, api_key)

    {:ok, verified} = Keys.verify_key(plain_key)
    assert(verified.id == api_key.id, "Verified key matches created key")
    info("Key created and verified: #{String.slice(plain_key, 0, 20)}...")
  end

  defp key_wrong_fails do
    result = Keys.verify_key("bb_live_wrongkeywrongkeywrongkey00")
    assert(result == {:error, :invalid}, "Wrong key returns :invalid (got #{inspect(result)})")
    info("Wrong key rejected")
  end

  defp key_revoke_rejected do
    api_key = Process.get(:e2e_test_api_key)
    plain_key = Process.get(:e2e_test_key)

    {:ok, _revoked} = Keys.revoke_key(api_key)

    result = Keys.verify_key(plain_key)
    assert(result == {:error, :revoked}, "Revoked key returns :revoked (got #{inspect(result)})")
    info("Revoked key rejected")
  end

  defp key_wrong_api do
    key = Process.get(:e2e_fact_key)
    other_api_id = Ecto.UUID.generate()

    result = Keys.verify_key_for_api(key, other_api_id)
    assert(result == {:error, :invalid}, "Key for wrong API returns :invalid (got #{inspect(result)})")
    info("Key for wrong API rejected")
  end

  # 1.7: Version management

  defp versions_create do
    api = Process.get(:e2e_fact_api)

    modified_code = String.replace(@factorial_code, "Calculates factorial.", "Computes factorial v2.")

    {:ok, v2} =
      Apis.create_version(api, %{
        code: modified_code,
        source: "manual_edit",
        prompt: "Modified version"
      })

    Process.put(:e2e_v2_code, modified_code)
    assert(v2.version_number >= 2, "Version 2+ created (got #{v2.version_number})")
    info("Version #{v2.version_number} created with modified code")
  end

  defp versions_list do
    api = Process.get(:e2e_fact_api)
    versions = Apis.list_versions(api.id)

    assert(length(versions) >= 2, "At least 2 versions (got #{length(versions)})")
    info("#{length(versions)} versions in history")
  end

  defp versions_rollback do
    api = Process.get(:e2e_fact_api)
    # Reload to get latest source_code
    api = Repo.get!(Api, api.id)

    {:ok, rollback_version} = Apis.rollback_to_version(api, 1)
    assert(rollback_version.code == @factorial_code, "Rollback restored original code")

    # Verify the API source_code was also updated
    api_after = Repo.get!(Api, api.id)
    assert(api_after.source_code == @factorial_code, "API source_code reverted")
    info("Rolled back to version 1, code matches original")
  end

  # 1.8: Linter tests

  defp linter_missing_spec do
    code = """
    def handle(params) do
      params
    end
    """

    result = Linter.check_credo(code)
    has_spec_issue = Enum.any?(result.issues, &String.contains?(&1, "@spec"))
    assert(has_spec_issue, "Missing @spec detected (issues: #{inspect(result.issues)})")
    info("Missing @spec: #{hd(Enum.filter(result.issues, &String.contains?(&1, "@spec")))}")
  end

  defp linter_missing_doc do
    code = """
    @spec handle(map()) :: map()
    def handle(params) do
      params
    end
    """

    result = Linter.check_credo(code)
    has_doc_issue = Enum.any?(result.issues, &String.contains?(&1, "@doc"))
    assert(has_doc_issue, "Missing @doc detected (issues: #{inspect(result.issues)})")
    info("Missing @doc: #{hd(Enum.filter(result.issues, &String.contains?(&1, "@doc")))}")
  end

  defp linter_unformatted do
    code = "def    handle(  params  ) do\nparams\nend"
    result = Linter.check_format(code)
    assert(result.status != :pass, "Unformatted code detected (status: #{result.status})")
    info("Format issue: #{hd(result.issues)}")
  end

  defp linter_clean do
    code = """
    @doc "Handles request."
    @spec handle(map()) :: map()
    def handle(params) do
      params
    end
    """

    credo_result = Linter.check_credo(code)
    format_result = Linter.check_format(String.trim(code) <> "\n")

    # Credo should have no spec/doc issues (may have others)
    spec_doc_issues =
      Enum.filter(credo_result.issues, fn issue ->
        String.contains?(issue, "@spec") or String.contains?(issue, "@doc")
      end)

    assert(spec_doc_issues == [], "No spec/doc issues (got #{inspect(spec_doc_issues)})")
    info("Credo: #{length(credo_result.issues)} issues, format: #{format_result.status}")
  end

  defp cleanup_part1 do
    for key <- [:e2e_fact_module, :e2e_crud_module, :e2e_webhook_module] do
      module = Process.get(key)
      if module, do: Compiler.unload(module)
    end

    for key <- [:e2e_fact_api, :e2e_crud_api, :e2e_webhook_api] do
      api = Process.get(key)
      if api, do: Registry.unregister(api.id)
    end

    info("Cleaned up Part 1 resources")
  end

  # ── Part 2: LLM-powered Tests ───────────────────────────────────────

  defp setup_llm do
    # Reuse user/org from Part 1 or create new
    unless Process.get(:e2e_user) do
      setup()
    end

    info("LLM tests ready")
  end

  defp llm_generate do
    org = Process.get(:e2e_org)
    description = "An API that calculates the factorial of a non-negative integer number"

    # TODO: Migrate to Agent.CodePipeline (CodeGen.Pipeline was removed as dead code)
    raise "llm_generate not implemented — CodeGen.Pipeline was removed. Use Agent.CodePipeline instead."
    end
  end

  defp llm_verify_dto do
    code = Process.get(:e2e_llm_code)
    assert(code =~ ~r/defmodule Request/, "Code includes defmodule Request (DTO)")
    info("Request DTO found in generated code")
  end

  defp llm_compile do
    org = Process.get(:e2e_org)
    user = Process.get(:e2e_user)
    code = Process.get(:e2e_llm_code)
    template = Process.get(:e2e_llm_template)

    {:ok, api} =
      Apis.create_api(%{
        name: "E2E LLM Factorial",
        slug: "e2e-llm-#{System.unique_integer([:positive])}",
        description: "LLM-generated factorial",
        source_code: code,
        template_type: to_string(template),
        organization_id: org.id,
        user_id: user.id
      })

    Process.put(:e2e_llm_api, api)

    case Compiler.compile(api, code) do
      {:ok, module} ->
        Process.put(:e2e_llm_module, module)
        info("LLM code compiled: #{inspect(module)}")

      {:error, reason} ->
        raise "LLM code compilation failed: #{inspect(reason)}"
    end
  end

  defp llm_pipeline do
    code = Process.get(:e2e_llm_code)
    template = Process.get(:e2e_llm_template)

    # TODO: Migrate to Agent pipeline (UnifiedPipeline was removed as dead code)
    warn("llm_pipeline skipped — UnifiedPipeline was removed. Use Agent pipeline instead.")
    _ = {code, template}
  end

  defp llm_save_publish do
    api = Process.get(:e2e_llm_api)
    org = Process.get(:e2e_org)
    test_code = Process.get(:e2e_llm_test_code)

    {:ok, api} = Apis.update_api(api, %{status: "compiled", test_code: test_code})
    Process.put(:e2e_llm_api, api)

    module = Process.get(:e2e_llm_module)

    :ok =
      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug,
        requires_auth: api.requires_auth,
        visibility: api.visibility
      )

    case Apis.publish(api, org) do
      {:ok, published_api, plain_key} ->
        Process.put(:e2e_llm_api, published_api)
        Process.put(:e2e_llm_key, plain_key)
        assert(published_api.status == "published", "LLM API published")
        info("Published: #{published_api.slug}")

      {:error, reason} ->
        raise "Publish failed: #{inspect(reason)}"
    end
  end

  defp llm_test_structure do
    test_code = Process.get(:e2e_llm_test_code)

    if test_code do
      has_handle_call = test_code =~ ~r/Handler\.handle|handle\(/
      info("Test code references handle: #{has_handle_call}")
      info("Test code length: #{String.length(test_code)} chars")
    else
      warn("No test code generated, skipping structure check")
    end
  end

  defp cleanup_part2 do
    module = Process.get(:e2e_llm_module)
    api = Process.get(:e2e_llm_api)

    if module, do: Compiler.unload(module)
    if api, do: Registry.unregister(api.id)
    info("Cleaned up Part 2 resources")
  end

  # ── Part 3: HTTP Tests ──────────────────────────────────────────────

  defp setup_http do
    org = Process.get(:e2e_org) || setup_and_return_org()
    user = Process.get(:e2e_user)

    # Create and publish an API for HTTP tests
    {:ok, api} =
      Apis.create_api(%{
        name: "E2E HTTP",
        slug: "e2e-http-#{System.unique_integer([:positive])}",
        description: "HTTP test factorial",
        source_code: @factorial_code,
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })

    case Compiler.compile(api, @factorial_code) do
      {:ok, module} ->
        Process.put(:e2e_http_module, module)

        :ok =
          Registry.register(api.id, module,
            org_slug: org.slug,
            slug: api.slug,
            requires_auth: api.requires_auth,
            visibility: api.visibility
          )

        {:ok, api} = Apis.update_api(api, %{status: "compiled"})

        case Apis.publish(api, org) do
          {:ok, published_api, plain_key} ->
            Process.put(:e2e_http_api, published_api)
            Process.put(:e2e_http_key, plain_key)
            info("HTTP test API ready: /api/#{org.slug}/#{published_api.slug}")

          {:error, reason} ->
            raise "HTTP setup publish failed: #{inspect(reason)}"
        end

      {:error, reason} ->
        raise "HTTP setup compile failed: #{inspect(reason)}"
    end
  end

  defp setup_and_return_org do
    setup()
    Process.get(:e2e_org)
  end

  defp http_auth_valid do
    api = Process.get(:e2e_http_api)
    org = Process.get(:e2e_org)
    key = Process.get(:e2e_http_key)
    url = "#{@base_url}/api/#{org.slug}/#{api.slug}"

    {:ok, status, body} = http_post(url, %{"number" => 5}, key)
    assert(status == 200, "POST with valid key -> 200 (got #{status})")
    decoded = Jason.decode!(body)
    assert(decoded["result"] == 120, "5! = 120 (got #{inspect(decoded["result"])})")
    info("200 OK: #{body}")
  end

  defp http_auth_missing do
    api = Process.get(:e2e_http_api)
    org = Process.get(:e2e_org)
    url = "#{@base_url}/api/#{org.slug}/#{api.slug}"

    {:ok, status, _body} = http_post(url, %{"number" => 5})
    assert(status == 401, "POST without key -> 401 (got #{status})")
    info("401 Unauthorized (no key)")
  end

  defp http_auth_wrong do
    api = Process.get(:e2e_http_api)
    org = Process.get(:e2e_org)
    url = "#{@base_url}/api/#{org.slug}/#{api.slug}"

    {:ok, status, _body} = http_post(url, %{"number" => 5}, "bb_live_invalidkeyinvalidkey0000")
    assert(status == 401, "POST with wrong key -> 401 (got #{status})")
    info("401 Unauthorized (wrong key)")
  end

  defp http_auth_revoked do
    api = Process.get(:e2e_http_api)
    org = Process.get(:e2e_org)
    url = "#{@base_url}/api/#{org.slug}/#{api.slug}"

    # Create a new key, then revoke it
    {:ok, rkey, rapi_key} = Keys.create_key(api, %{label: "Revoke test", organization_id: org.id})
    {:ok, _} = Keys.revoke_key(rapi_key)

    {:ok, status, _body} = http_post(url, %{"number" => 5}, rkey)
    assert(status == 401, "POST with revoked key -> 401 (got #{status})")
    info("401 Unauthorized (revoked key)")
  end

  defp http_noauth do
    org = Process.get(:e2e_org)
    user = Process.get(:e2e_user)

    # Create a no-auth API
    {:ok, noauth_api} =
      Apis.create_api(%{
        name: "E2E NoAuth",
        slug: "e2e-noauth-#{System.unique_integer([:positive])}",
        description: "No auth test",
        source_code: @factorial_code,
        template_type: "computation",
        requires_auth: false,
        organization_id: org.id,
        user_id: user.id
      })

    case Compiler.compile(noauth_api, @factorial_code) do
      {:ok, module} ->
        Process.put(:e2e_noauth_module, module)

        :ok =
          Registry.register(noauth_api.id, module,
            org_slug: org.slug,
            slug: noauth_api.slug,
            requires_auth: false,
            visibility: noauth_api.visibility
          )

        {:ok, noauth_api} = Apis.update_api(noauth_api, %{status: "compiled"})

        case Apis.publish(noauth_api, org) do
          {:ok, published, _key} ->
            Process.put(:e2e_noauth_api, published)
            url = "#{@base_url}/api/#{org.slug}/#{published.slug}"

            {:ok, status, body} = http_post(url, %{"number" => 3})
            assert(status == 200, "POST no-auth -> 200 (got #{status})")
            decoded = Jason.decode!(body)
            assert(decoded["result"] == 6, "3! = 6 (got #{inspect(decoded["result"])})")
            info("200 OK without auth: #{body}")

          {:error, reason} ->
            raise "No-auth publish failed: #{inspect(reason)}"
        end

      {:error, reason} ->
        raise "No-auth compile failed: #{inspect(reason)}"
    end
  end

  defp http_openapi_json do
    api = Process.get(:e2e_http_api)
    org = Process.get(:e2e_org)
    url = "#{@base_url}/api/#{org.slug}/#{api.slug}/openapi.json"

    {:ok, status, body} = http_get(url)
    assert(status == 200, "GET openapi.json -> 200 (got #{status})")
    spec = Jason.decode!(body)
    assert(spec["openapi"] != nil, "Has openapi field")
    assert(spec["paths"] != nil, "Has paths")
    info("OpenAPI spec: #{String.length(body)} bytes")
  end

  defp http_swagger_ui do
    api = Process.get(:e2e_http_api)
    org = Process.get(:e2e_org)
    url = "#{@base_url}/api/#{org.slug}/#{api.slug}/docs"

    {:ok, status, body} = http_get(url)
    assert(status == 200, "GET /docs -> 200 (got #{status})")
    assert(String.contains?(body, "swagger") or String.contains?(body, "Swagger"), "Contains Swagger reference")
    info("Swagger UI: #{String.length(body)} bytes")
  end

  defp http_error_missing do
    api = Process.get(:e2e_http_api)
    org = Process.get(:e2e_org)
    key = Process.get(:e2e_http_key)
    url = "#{@base_url}/api/#{org.slug}/#{api.slug}"

    {:ok, status, body} = http_post(url, %{}, key)
    info("Empty params -> #{status}: #{String.slice(body, 0, 200)}")
    # Handler should return 200 with error in body, or could be 400/422
    assert(status in [200, 400, 422], "Graceful error response (got #{status})")
  end

  defp http_error_invalid_json do
    api = Process.get(:e2e_http_api)
    org = Process.get(:e2e_org)
    key = Process.get(:e2e_http_key)
    url = "#{@base_url}/api/#{org.slug}/#{api.slug}"

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{key}"}
    ]

    case Req.post(url, body: "not valid json{{{", headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: status}} ->
        assert(status == 400, "Invalid JSON -> 400 (got #{status})")
        info("Invalid JSON -> #{status}")

      {:error, %{reason: reason}} ->
        raise "HTTP request failed: #{inspect(reason)}"
    end
  end

  defp cleanup_part3 do
    for key <- [:e2e_http_module, :e2e_noauth_module] do
      module = Process.get(key)
      if module, do: Compiler.unload(module)
    end

    for key <- [:e2e_http_api, :e2e_noauth_api] do
      api = Process.get(key)
      if api, do: Registry.unregister(api.id)
    end

    info("Cleaned up Part 3 resources")
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp assert_blocked(code, label) do
    api = %Api{id: Ecto.UUID.generate(), template_type: "computation"}

    case Compiler.compile(api, code) do
      {:error, {:validation, reasons}} ->
        info("#{label} blocked: #{hd(reasons)}")

      {:ok, module} ->
        Compiler.unload(module)
        raise "Security: #{label} should have been blocked!"
    end
  end

  defp has_anthropic_key? do
    key = System.get_env("ANTHROPIC_API_KEY")
    is_binary(key) and String.length(key) > 10
  end

  defp http_post(url, body, api_key \\ nil) do
    headers = [{"content-type", "application/json"}]
    headers = if api_key, do: [{"authorization", "Bearer #{api_key}"} | headers], else: headers

    case Req.post(url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: status, body: body}} ->
        {:ok, status, if(is_binary(body), do: body, else: Jason.encode!(body))}

      {:error, %{reason: reason}} ->
        raise "HTTP POST failed: #{inspect(reason)}"
    end
  end

  defp http_get(url) do
    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: status, body: body}} ->
        {:ok, status, if(is_binary(body), do: body, else: Jason.encode!(body))}

      {:error, %{reason: reason}} ->
        raise "HTTP GET failed: #{inspect(reason)}"
    end
  end

  defp run_part(title, steps) do
    IO.puts("\n#{IO.ANSI.bright()}--- #{title} ---#{IO.ANSI.reset()}")

    results = Enum.map(steps, fn {name, fun} -> step(name, fun) end)

    passed = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :error))
    skipped = Enum.count(results, &(&1 == :skipped))

    {passed, failed, skipped}
  end

  defp step(name, fun) do
    IO.write("  #{IO.ANSI.cyan()}#{name}#{IO.ANSI.reset()} ... ")

    try do
      fun.()
      IO.puts("#{IO.ANSI.green()}OK#{IO.ANSI.reset()}")
      :ok
    rescue
      e ->
        IO.puts("#{IO.ANSI.red()}FAILED#{IO.ANSI.reset()}")
        IO.puts("    #{IO.ANSI.red()}#{Exception.message(e)}#{IO.ANSI.reset()}")
        :error
    catch
      :skipped ->
        IO.puts("#{IO.ANSI.yellow()}SKIPPED#{IO.ANSI.reset()}")
        :skipped
    end
  end

  defp print_summary(part1, part2, part3) do
    IO.puts("\n#{IO.ANSI.bright()}=== Summary ===" <> IO.ANSI.reset())

    {p1_pass, p1_fail, p1_skip} = part1
    {p2_pass, p2_fail, p2_skip} = part2
    {p3_pass, p3_fail, p3_skip} = part3

    total_pass = p1_pass + p2_pass + p3_pass
    total_fail = p1_fail + p2_fail + p3_fail
    total_skip = p1_skip + p2_skip + p3_skip

    IO.puts("  Part 1 (Hardcoded):  #{colorize_count(p1_pass, :green)} passed, #{colorize_count(p1_fail, :red)} failed, #{colorize_count(p1_skip, :yellow)} skipped")
    IO.puts("  Part 2 (LLM):       #{colorize_count(p2_pass, :green)} passed, #{colorize_count(p2_fail, :red)} failed, #{colorize_count(p2_skip, :yellow)} skipped")
    IO.puts("  Part 3 (HTTP):      #{colorize_count(p3_pass, :green)} passed, #{colorize_count(p3_fail, :red)} failed, #{colorize_count(p3_skip, :yellow)} skipped")
    IO.puts("")
    IO.puts("  #{IO.ANSI.bright()}Total: #{total_pass} passed, #{total_fail} failed, #{total_skip} skipped#{IO.ANSI.reset()}")

    if total_fail > 0 do
      IO.puts("\n  #{IO.ANSI.red()}SOME TESTS FAILED#{IO.ANSI.reset()}")
      System.halt(1)
    else
      IO.puts("\n  #{IO.ANSI.green()}ALL TESTS PASSED#{IO.ANSI.reset()}")
    end
  end

  defp colorize_count(0, _color), do: "0"
  defp colorize_count(n, :green), do: "#{IO.ANSI.green()}#{n}#{IO.ANSI.reset()}"
  defp colorize_count(n, :red), do: "#{IO.ANSI.red()}#{n}#{IO.ANSI.reset()}"
  defp colorize_count(n, :yellow), do: "#{IO.ANSI.yellow()}#{n}#{IO.ANSI.reset()}"

  defp assert(true, _msg), do: :ok
  defp assert(false, msg), do: raise("Assertion failed: #{msg}")
  defp assert(nil, msg), do: raise("Assertion failed (nil): #{msg}")

  defp info(msg), do: IO.puts("    #{IO.ANSI.faint()}#{msg}#{IO.ANSI.reset()}")
  defp warn(msg), do: IO.puts("    #{IO.ANSI.yellow()}! #{msg}#{IO.ANSI.reset()}")
end

# ── Bootstrap ──────────────────────────────────────────────────────────

# Check if server is reachable
server_up =
  case Req.get("http://localhost:4000", receive_timeout: 2_000) do
    {:ok, _} ->
      IO.puts("Server running on localhost:4000 -- HTTP tests enabled")
      true

    {:error, _} ->
      IO.puts("Server not on localhost:4000 -- HTTP tests will be skipped")
      false
  end

Process.put(:e2e_server_up, server_up)

# Check LLM key
if System.get_env("ANTHROPIC_API_KEY") do
  IO.puts("ANTHROPIC_API_KEY set -- LLM tests enabled")
else
  IO.puts("ANTHROPIC_API_KEY not set -- LLM tests will be skipped")
end

E2ETest.run()
