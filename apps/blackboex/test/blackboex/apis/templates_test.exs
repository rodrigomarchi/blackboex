defmodule Blackboex.Apis.TemplatesTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis.Templates

  describe "list/0" do
    test "returns a non-empty list of templates" do
      templates = Templates.list()
      assert is_list(templates)
      assert templates != []
    end

    test "each template has required keys" do
      for t <- Templates.list() do
        assert is_binary(t.id) and t.id != ""
        assert is_binary(t.name) and t.name != ""
        assert is_binary(t.description) and t.description != ""
        assert is_binary(t.category) and t.category != ""
        assert is_binary(t.method) and t.method != ""
        assert is_map(t.files)
        assert is_map(t.param_schema)
        assert is_map(t.example_request)
        assert is_map(t.example_response)
        assert is_map(t.validation_report)
      end
    end

    test "each template files map has all required file keys" do
      for t <- Templates.list() do
        assert is_binary(t.files.handler) and t.files.handler != "", "handler missing for #{t.id}"
        assert is_binary(t.files.helpers), "helpers missing for #{t.id}"

        assert is_binary(t.files.request_schema) and t.files.request_schema != "",
               "request_schema missing for #{t.id}"

        assert is_binary(t.files.response_schema) and t.files.response_schema != "",
               "response_schema missing for #{t.id}"

        assert is_binary(t.files.test) and t.files.test != "", "test missing for #{t.id}"
        assert is_binary(t.files.readme) and t.files.readme != "", "readme missing for #{t.id}"
      end
    end
  end

  describe "get/1" do
    test "returns the correct template by id" do
      t = Templates.list() |> hd()
      assert Templates.get(t.id) == t
    end

    test "returns nil for unknown id" do
      assert Templates.get("non-existent-template-id") == nil
    end

    test "returns nil for empty string" do
      assert Templates.get("") == nil
    end
  end

  describe "categories/0" do
    test "returns a non-empty list of category strings" do
      cats = Templates.categories()
      assert is_list(cats)
      assert cats != []
      assert Enum.all?(cats, &is_binary/1)
    end

    test "all returned categories are present in template list" do
      present = Templates.list() |> Enum.map(& &1.category) |> MapSet.new()

      for cat <- Templates.categories() do
        assert MapSet.member?(present, cat), "category #{cat} has no templates"
      end
    end

    test "each category appears at most once" do
      cats = Templates.categories()
      assert cats == Enum.uniq(cats)
    end
  end

  describe "list_by_category/0" do
    test "returns list of {category, templates} tuples" do
      result = Templates.list_by_category()
      assert is_list(result)

      for {cat, templates} <- result do
        assert is_binary(cat)
        assert is_list(templates)
        assert templates != []
      end
    end

    test "covers all templates" do
      all_ids = Templates.list() |> Enum.map(& &1.id) |> MapSet.new()

      grouped_ids =
        Templates.list_by_category()
        |> Enum.flat_map(fn {_cat, templates} -> Enum.map(templates, & &1.id) end)
        |> MapSet.new()

      assert grouped_ids == all_ids
    end

    test "templates in each group belong to that category" do
      for {cat, templates} <- Templates.list_by_category() do
        for t <- templates do
          assert t.category == cat, "template #{t.id} has category #{t.category}, expected #{cat}"
        end
      end
    end
  end

  describe "template data integrity" do
    test "all param_schema maps are non-empty" do
      for t <- Templates.list() do
        assert map_size(t.param_schema) > 0, "param_schema empty for #{t.id}"
      end
    end

    test "all example_request maps are non-empty" do
      for t <- Templates.list() do
        assert map_size(t.example_request) > 0, "example_request empty for #{t.id}"
      end
    end

    test "all example_response maps are non-empty" do
      for t <- Templates.list() do
        assert map_size(t.example_response) > 0, "example_response empty for #{t.id}"
      end
    end

    test "all validation_report maps have overall: pass" do
      for t <- Templates.list() do
        assert t.validation_report["overall"] == "pass",
               "validation_report overall not pass for #{t.id}"
      end
    end

    test "all handler code compiles without errors" do
      for t <- Templates.list() do
        result = with_temp_module(t.files.handler, &silent_compile/1)
        assert match?({:ok, _, _}, result), "handler does not compile for #{t.id}"
      end
    end

    test "all helpers code compiles without errors" do
      for t <- Templates.list() do
        if t.files.helpers != "" do
          result = silent_compile(t.files.helpers)
          assert is_list(result), "helpers do not compile for #{t.id}"
        end
      end
    end

    test "all request_schema code compiles without errors" do
      for t <- Templates.list() do
        assert match?([_ | _], silent_compile(t.files.request_schema)),
               "request_schema does not compile for #{t.id}"
      end
    end

    test "all response_schema code compiles without errors" do
      for t <- Templates.list() do
        assert match?([_ | _], silent_compile(t.files.response_schema)),
               "response_schema does not compile for #{t.id}"
      end
    end
  end

  # Helper to attempt compilation, returning :ok or :error without leaking modules
  defp with_temp_module(code, fun) do
    result = fun.(code)
    {:ok, :compiled, result}
  rescue
    e -> {:error, :compile_error, e}
  end

  # Each template fragment (handler, helpers, request, response) is compiled
  # in isolation, so cross-fragment references are *expected* to be undefined,
  # and reusing module names like `Handler`/`Request`/`Response`/`Helpers`
  # across templates causes "redefining module" warnings. Both kinds are
  # noise here — we only care whether the code parses + compiles. Capture
  # the diagnostics so they don't pollute the suite output.
  defp silent_compile(code) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      {result, _diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(code) end)
      result
    after
      Code.put_compiler_option(:ignore_module_conflict, previous || false)
    end
  end
end
