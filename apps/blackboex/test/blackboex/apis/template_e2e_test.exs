defmodule Blackboex.Apis.TemplateE2ETest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :capture_log

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.Apis.Templates
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.Linter
  alias Blackboex.Testing.TestRunner

  setup do
    Registry.clear()

    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Template Test Org",
        slug: "tmpl-test"
      })

    %{user: user, org: org}
  end

  # ---------------------------------------------------------------------------
  # Helper: create, compile, publish, and register a template API
  # ---------------------------------------------------------------------------

  defp create_and_publish_template(org, user, template_id) do
    template = Templates.get(template_id)
    attrs = %{name: template.name, organization_id: org.id, user_id: user.id}
    {:ok, api} = Apis.create_api_from_template(attrs, template_id)

    # Compile source files (required before publish can serve requests)
    source_files = Apis.list_source_files(api.id)
    {:ok, module} = Compiler.compile_files(api, source_files)

    # Register in Registry so DynamicApiRouter can find it
    Registry.register(api.id, module,
      org_slug: org.slug,
      slug: api.slug,
      requires_auth: api.requires_auth,
      visibility: api.visibility
    )

    # Publish
    {:ok, published_api} = Apis.publish(api, org)

    on_exit(fn ->
      try do
        Compiler.unload(module)
      rescue
        _ -> :ok
      end
    end)

    {published_api, template}
  end

  # ---------------------------------------------------------------------------
  # Core e2e: full platform pipeline for each template
  # Mirrors Agent pipeline: compile → format → credo → test → publish → HTTP
  # ---------------------------------------------------------------------------

  describe "all templates: full platform pipeline (compile → format → lint → test → publish → HTTP 200)" do
    for template <- Templates.list() do
      @template_id template.id

      test "#{template.id}: full pipeline passes",
           %{conn: conn, user: user, org: org} do
        t = Templates.get(@template_id)
        attrs = %{name: t.name, organization_id: org.id, user_id: user.id}
        {:ok, api} = Apis.create_api_from_template(attrs, @template_id)

        source_files = Apis.list_source_files(api.id)
        test_files = Apis.list_test_files(api.id)

        # 1. COMPILE — same as CodePipeline step
        assert {:ok, module} = Compiler.compile_files(api, source_files),
               "#{@template_id}: compilation failed"

        # 2. FORMAT — check all source files pass mix format
        for file <- source_files do
          result = Linter.check_format(file.content)

          assert result.status in [:pass, :warn],
                 "#{@template_id}: #{file.path} format failed: #{inspect(result.issues)}"
        end

        # 3. CREDO — check all source files pass credo linter
        for file <- source_files do
          result = Linter.check_credo(file.content)

          assert result.status in [:pass, :warn],
                 "#{@template_id}: #{file.path} credo failed: #{inspect(result.issues)}"
        end

        # 4. TESTS — run template's test suite via TestRunner
        # TestRunner wraps handler_code in defmodule Handler_N do ... end,
        # so we strip the outer defmodule Handler wrapper from handler.ex
        # and concatenate all source files as bare content. This matches
        # how single-file APIs work in the CodePipeline.
        if Enum.any?(test_files) do
          # Order matters: helpers/schemas first, handler last (stripped).
          # TestRunner wraps in defmodule Handler_N, so:
          # - Request/Response/Helpers keep wrappers → become Handler_N.Request etc.
          # - Handler wrapper stripped → functions live at Handler_N.handle/1
          {handler_files, helper_files} =
            Enum.split_with(source_files, &(&1.path == "/src/handler.ex"))

          handler_code =
            (Enum.map(helper_files, & &1.content) ++
               Enum.map(handler_files, &strip_defmodule_wrapper(&1.content)))
            |> Enum.join("\n\n")

          # Qualify bare module refs so TestRunner's Handler. → Handler_N. rewrite works
          test_code =
            test_files
            |> Enum.map_join("\n\n", & &1.content)
            |> String.replace("Request.changeset", "Handler.Request.changeset")
            |> String.replace("Response.", "Handler.Response.")

          test_results =
            TestRunner.run(test_code,
              handler_code: handler_code,
              timeout: 30_000
            )

          case test_results do
            {:ok, results} when is_list(results) ->
              failed = Enum.reject(results, &(&1.status == "passed"))

              assert failed == [],
                     "#{@template_id}: #{length(failed)} test(s) failed: #{inspect(Enum.map(failed, & &1.name))}"

            {:error, :compile_error, msg} ->
              flunk("#{@template_id}: test compile error: #{msg}")

            {:error, reason} ->
              flunk("#{@template_id}: test runner error: #{inspect(reason)}")
          end
        end

        # 5. PUBLISH — register in Registry
        Registry.register(api.id, module,
          org_slug: org.slug,
          slug: api.slug,
          requires_auth: api.requires_auth,
          visibility: api.visibility
        )

        {:ok, _published} = Apis.publish(api, org)

        on_exit(fn ->
          try do
            Compiler.unload(module)
          rescue
            _ -> :ok
          end
        end)

        # 6. HTTP REQUEST — real POST through the full stack
        conn =
          conn
          |> put_req_header("content-type", "application/json")
          |> post("/api/#{org.slug}/#{api.slug}", Jason.encode!(t.example_request))

        response = json_response(conn, 200)

        # Verify response contains the same top-level keys as example_response
        expected_keys =
          t.example_response
          |> Map.keys()
          |> Enum.map(&to_string/1)
          |> MapSet.new()

        actual_keys = response |> Map.keys() |> MapSet.new()

        assert MapSet.subset?(expected_keys, actual_keys),
               "#{@template_id}: missing keys. expected: #{inspect(MapSet.to_list(expected_keys))}, got: #{inspect(MapSet.to_list(actual_keys))}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Detailed e2e for cotacao-frete (reference template)
  # ---------------------------------------------------------------------------

  describe "cotacao-frete: detailed HTTP e2e" do
    test "returns 200 with opcoes list", %{conn: conn, user: user, org: org} do
      {api, template} = create_and_publish_template(org, user, "cotacao-frete")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/#{org.slug}/#{api.slug}",
          Jason.encode!(template.example_request)
        )

      response = json_response(conn, 200)
      assert Map.has_key?(response, "opcoes") or Map.has_key?(response, "result")
    end

    test "returns 200 with all 6 files created", %{user: user, org: org} do
      attrs = %{name: "File Check", organization_id: org.id, user_id: user.id}
      {:ok, api} = Apis.create_api_from_template(attrs, "cotacao-frete")

      files = Apis.list_files(api.id)
      paths = Enum.map(files, & &1.path) |> MapSet.new()

      assert MapSet.member?(paths, "/src/handler.ex")
      assert MapSet.member?(paths, "/src/helpers.ex")
      assert MapSet.member?(paths, "/src/request_schema.ex")
      assert MapSet.member?(paths, "/src/response_schema.ex")
      assert MapSet.member?(paths, "/test/handler_test.ex")
      assert MapSet.member?(paths, "/README.md")
    end

    test "unpublished template API compiles on-demand and returns validation error",
         %{conn: conn, user: user, org: org} do
      attrs = %{name: "Unpublished", organization_id: org.id, user_id: user.id}
      {:ok, _api} = Apis.create_api_from_template(attrs, "cotacao-frete")

      # API with status "compiled" is compilable on-demand via compile_from_db
      # Sending empty params triggers validation error (not 404)
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/#{org.slug}/unpublished", Jason.encode!(%{}))

      response = json_response(conn, 200)
      assert response["error"] == "Validation failed"
    end
  end

  # ---------------------------------------------------------------------------
  # Template data integrity
  # ---------------------------------------------------------------------------

  describe "all templates: code compiles in sandbox" do
    for template <- Templates.list() do
      @template template

      test "#{template.id}: all source files compile via Compiler", %{user: user, org: org} do
        t = @template
        attrs = %{name: "#{t.name} Compile", organization_id: org.id, user_id: user.id}
        {:ok, api} = Apis.create_api_from_template(attrs, t.id)

        source_files = Apis.list_source_files(api.id)

        assert {:ok, _module} = Compiler.compile_files(api, source_files),
               "#{t.id}: failed to compile source files in sandbox"
      end
    end
  end

  describe "all templates: validation_report" do
    for template <- Templates.list() do
      @template template

      test "#{template.id}: overall is pass" do
        assert @template.validation_report["overall"] == "pass",
               "validation_report overall not pass for #{@template.id}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Virtual files
  # ---------------------------------------------------------------------------

  describe "virtual files" do
    test "list_files_with_virtual/1 returns source + virtual files", %{user: user, org: org} do
      attrs = %{name: "Virtual Files", organization_id: org.id, user_id: user.id}
      {:ok, api} = Apis.create_api_from_template(attrs, "cotacao-frete")

      all_files = Apis.list_files_with_virtual(api)
      paths = Enum.map(all_files, & &1.path) |> MapSet.new()

      assert MapSet.member?(paths, "/src/handler.ex")
      assert MapSet.member?(paths, "/README.md")
      assert MapSet.member?(paths, "/docs/param_schema.json")
      assert MapSet.member?(paths, "/docs/examples/request.json")
      assert MapSet.member?(paths, "/docs/examples/response.json")
    end
  end

  # Strips the outer `defmodule ModuleName do ... end` wrapper from code,
  # leaving inner content. Modules like Request, Response keep their wrappers.
  # Only strips Handler and Helpers top-level wrappers since TestRunner adds its own.
  defp strip_defmodule_wrapper(code) do
    # Match: defmodule Handler do\n...content...\nend (outermost)
    case Regex.run(~r/\Adefmodule (Handler|Helpers) do\n(.*)\nend\s*\z/s, code) do
      [_, _module_name, inner] -> inner
      _ -> code
    end
  end
end
