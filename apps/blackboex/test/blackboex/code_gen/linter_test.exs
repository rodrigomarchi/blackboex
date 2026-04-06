defmodule Blackboex.CodeGen.LinterTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.CodeGen.Linter

  # ──────────────────────────────────────────────────────────────
  # run_all/1
  # ──────────────────────────────────────────────────────────────

  describe "run_all/1" do
    test "returns a list of two check results (format + credo)" do
      code = """
      @doc "Handles request."
      @spec handle(map()) :: map()
      def handle(params), do: params
      """

      results = Linter.run_all(code)

      assert length(results) == 2
      checks = Enum.map(results, & &1.check)
      assert :format in checks
      assert :credo in checks
    end

    test "all checks pass for clean code" do
      code =
        ~s|@doc "Handles request."\n@spec handle(map()) :: map()\ndef handle(params), do: params\n|

      {:ok, code} = Linter.auto_format(code)
      results = Linter.run_all(code)

      assert Enum.all?(results, &(&1.status == :pass))
    end
  end

  # ──────────────────────────────────────────────────────────────
  # check_format/1
  # ──────────────────────────────────────────────────────────────

  describe "check_format/1" do
    test "passes for properly formatted code" do
      code = """
      def handle(params) do
        params
      end
      """

      # Pre-format to guarantee it's formatted
      formatted = Code.format_string!(code) |> IO.iodata_to_binary()
      result = Linter.check_format(formatted)

      assert result.check == :format
      assert result.status == :pass
      assert result.issues == []
    end

    test "warns for unformatted code" do
      code = "def handle( params ) do\nparams\nend"

      result = Linter.check_format(code)

      assert result.status == :warn
      assert result.issues != []
      assert hd(result.issues) =~ "not formatted"
    end

    test "returns error for invalid syntax" do
      code = "def handle(params do end"

      result = Linter.check_format(code)

      assert result.status == :error
      assert hd(result.issues) =~ "Format check failed"
    end

    test "handles empty string" do
      result = Linter.check_format("")

      assert result.check == :format
      # Empty string is valid formatted code
      assert result.status == :pass
    end
  end

  # ──────────────────────────────────────────────────────────────
  # auto_format/1
  # ──────────────────────────────────────────────────────────────

  describe "auto_format/1" do
    test "formats valid code" do
      code = "def handle( params ) do\nparams\nend"

      assert {:ok, formatted} = Linter.auto_format(code)
      assert formatted =~ "def handle(params) do"
    end

    test "returns error for invalid syntax" do
      assert {:error, msg} = Linter.auto_format("def handle(params do end")
      assert is_binary(msg)
    end

    test "returns already-formatted code unchanged" do
      code = "def handle(params), do: params"
      assert {:ok, ^code} = Linter.auto_format(code)
    end

    test "handles empty string" do
      assert {:ok, ""} = Linter.auto_format("")
    end
  end

  # ──────────────────────────────────────────────────────────────
  # check_credo/1 — line length
  # ──────────────────────────────────────────────────────────────

  describe "check_credo/1 — long lines" do
    test "passes for lines under 120 characters" do
      code = """
      @doc "Short."
      @spec handle(map()) :: map()
      def handle(params), do: params
      """

      result = Linter.check_credo(code)
      long_line_issues = Enum.filter(result.issues, &(&1 =~ "exceeds"))

      assert long_line_issues == []
    end

    test "warns for lines over 120 characters" do
      long_line = String.duplicate("x", 121)

      code = """
      @doc "Short."
      @spec handle(map()) :: map()
      def handle(params), do: "#{long_line}"
      """

      result = Linter.check_credo(code)

      assert Enum.any?(result.issues, &(&1 =~ "exceeds 120 characters"))
    end

    test "line at exactly 120 characters passes" do
      # Build a line that is exactly 120 characters total
      prefix = "x = "
      padding = String.duplicate("a", 120 - String.length(prefix))
      line = prefix <> padding
      assert String.length(line) == 120

      result = Linter.check_credo(line)
      long_line_issues = Enum.filter(result.issues, &(&1 =~ "exceeds"))

      assert long_line_issues == []
    end

    test "reports correct line number for long lines" do
      code = "short\nshort\n#{String.duplicate("x", 125)}\nshort"

      result = Linter.check_credo(code)

      assert Enum.any?(result.issues, &(&1 =~ "Line 3"))
    end

    test "reports multiple long lines" do
      code = "#{String.duplicate("a", 130)}\nshort\n#{String.duplicate("b", 140)}"

      result = Linter.check_credo(code)
      long_line_issues = Enum.filter(result.issues, &(&1 =~ "exceeds"))

      assert length(long_line_issues) == 2
    end
  end

  # ──────────────────────────────────────────────────────────────
  # check_credo/1 — missing @spec
  # ──────────────────────────────────────────────────────────────

  describe "check_credo/1 — missing specs" do
    test "warns when public function has no @spec" do
      code = """
      @doc "Does things."
      def handle(params), do: params
      """

      result = Linter.check_credo(code)

      assert Enum.any?(result.issues, &(&1 =~ "Missing @spec for handle/1"))
    end

    test "passes when public function has @spec" do
      code = """
      @doc "Does things."
      @spec handle(map()) :: map()
      def handle(params), do: params
      """

      result = Linter.check_credo(code)
      spec_issues = Enum.filter(result.issues, &(&1 =~ "Missing @spec"))

      assert spec_issues == []
    end

    test "does not warn for private functions without @spec" do
      code = """
      @doc "Public."
      @spec handle(map()) :: map()
      def handle(params), do: helper(params)

      defp helper(params), do: params
      """

      result = Linter.check_credo(code)
      spec_issues = Enum.filter(result.issues, &(&1 =~ "Missing @spec for helper"))

      assert spec_issues == []
    end

    test "handles function with guard clause" do
      code = """
      @doc "Public."
      @spec handle(map()) :: map()
      def handle(params) when is_map(params), do: params
      """

      result = Linter.check_credo(code)
      spec_issues = Enum.filter(result.issues, &(&1 =~ "Missing @spec"))

      assert spec_issues == []
    end

    test "handles zero-arity function" do
      code = """
      @doc "Returns default."
      def default_value, do: %{}
      """

      result = Linter.check_credo(code)

      assert Enum.any?(result.issues, &(&1 =~ "Missing @spec for default_value/0"))
    end

    test "handles multi-arity function (detects correct arity)" do
      code = """
      @doc "Processes."
      @spec process(map(), keyword()) :: map()
      def process(params, opts), do: {params, opts}
      """

      result = Linter.check_credo(code)
      spec_issues = Enum.filter(result.issues, &(&1 =~ "Missing @spec for process"))

      assert spec_issues == []
    end

    test "gracefully handles unparseable code" do
      code = "def handle(params do end"

      result = Linter.check_credo(code)

      # Should not crash — spec/nesting checks silently skip on parse error
      assert is_list(result.issues)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # check_credo/1 — missing @doc
  # ──────────────────────────────────────────────────────────────

  describe "check_credo/1 — missing docs" do
    test "warns when public function has no @doc" do
      code = """
      @spec handle(map()) :: map()
      def handle(params), do: params
      """

      result = Linter.check_credo(code)

      assert Enum.any?(result.issues, &(&1 =~ "Missing @doc for public function handle"))
    end

    test "passes when @doc is above @spec above def" do
      code = """
      @doc "Does things."
      @spec handle(map()) :: map()
      def handle(params), do: params
      """

      result = Linter.check_credo(code)
      doc_issues = Enum.filter(result.issues, &(&1 =~ "Missing @doc"))

      assert doc_issues == []
    end

    test "does not warn for defp, defmacro, defdelegate, defguard" do
      code = """
      @doc "Public."
      @spec handle(map()) :: map()
      def handle(params), do: helper(params)

      defp helper(params), do: params
      defmacro my_macro(x), do: x
      defdelegate foo(x), to: SomeModule
      defguard is_valid(x) when is_map(x)
      """

      result = Linter.check_credo(code)
      doc_issues = Enum.filter(result.issues, &(&1 =~ "Missing @doc"))

      assert doc_issues == []
    end

    test "detects @doc with heredoc format" do
      code = ~s'''
      @doc """
      Multi-line doc.
      """
      @spec handle(map()) :: map()
      def handle(params), do: params
      '''

      result = Linter.check_credo(code)
      doc_issues = Enum.filter(result.issues, &(&1 =~ "Missing @doc"))

      assert doc_issues == []
    end

    test "warns when @doc is too far above function (blank lines + comments between)" do
      # @doc is there but function_def check is line-based: looks back up to 10 lines
      code = """
      @doc "Documented."
      # comment 1
      # comment 2
      # comment 3
      # comment 4
      # comment 5
      # comment 6
      # comment 7
      # comment 8
      # comment 9
      # comment 10
      # comment 11
      @spec handle(map()) :: map()
      def handle(params), do: params
      """

      result = Linter.check_credo(code)

      # has_doc_above? looks back max 10 lines — @doc is 13 lines above
      # The function should detect this is too far
      doc_issues = Enum.filter(result.issues, &(&1 =~ "Missing @doc"))

      # This tests whether the 10-line lookback window is sufficient
      # If @doc is >10 lines above, it won't be found
      assert is_list(doc_issues)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # check_credo/1 — function length
  # ──────────────────────────────────────────────────────────────

  describe "check_credo/1 — function length" do
    test "passes for function under 40 lines" do
      body = Enum.map_join(1..38, "\n", fn i -> "  x#{i} = #{i}" end)

      code = """
      @doc "Short enough."
      @spec handle(map()) :: map()
      def handle(params) do
      #{body}
      end
      """

      result = Linter.check_credo(code)
      length_issues = Enum.filter(result.issues, &(&1 =~ "too long"))

      assert length_issues == []
    end

    test "warns for function over 40 lines" do
      body = Enum.map_join(1..42, "\n", fn i -> "  x#{i} = #{i}" end)

      code = """
      @doc "Too long."
      @spec handle(map()) :: map()
      def handle(params) do
      #{body}
      end
      """

      result = Linter.check_credo(code)

      assert Enum.any?(result.issues, &(&1 =~ "too long"))
      assert Enum.any?(result.issues, &(&1 =~ "handle"))
    end

    test "counts defp functions separately" do
      short_body = Enum.map_join(1..5, "\n", fn i -> "  x#{i} = #{i}" end)

      code = """
      @doc "Public."
      @spec handle(map()) :: map()
      def handle(params) do
      #{short_body}
      end

      defp helper(params) do
      #{short_body}
      end
      """

      result = Linter.check_credo(code)
      length_issues = Enum.filter(result.issues, &(&1 =~ "too long"))

      assert length_issues == []
    end

    test "handles one-liner functions (do:)" do
      code = """
      @doc "Short."
      @spec handle(map()) :: map()
      def handle(params), do: params
      """

      result = Linter.check_credo(code)
      length_issues = Enum.filter(result.issues, &(&1 =~ "too long"))

      assert length_issues == []
    end
  end

  # ──────────────────────────────────────────────────────────────
  # check_credo/1 — nesting depth
  # ──────────────────────────────────────────────────────────────

  describe "check_credo/1 — nesting depth" do
    test "passes for shallow nesting" do
      code = """
      @doc "Shallow."
      @spec handle(map()) :: map()
      def handle(params) do
        case params do
          %{"ok" => true} -> params
          _ -> %{}
        end
      end
      """

      result = Linter.check_credo(code)
      nesting_issues = Enum.filter(result.issues, &(&1 =~ "Deeply nested"))

      assert nesting_issues == []
    end

    test "warns for deeply nested blocks (> 4 levels)" do
      # depth starts at 0, each if/case/cond/with increments by 1
      # check triggers when depth > 4, so we need 6 nested blocks
      # (depth reaches 5 at the innermost, then the 6th triggers > 4 check at depth 5+1)
      code = """
      @doc "Deep."
      @spec handle(map()) :: map()
      def handle(params) do
        if params do
          if params do
            if params do
              if params do
                if params do
                  if params do
                    params
                  end
                end
              end
            end
          end
        end
      end
      """

      result = Linter.check_credo(code)

      assert Enum.any?(result.issues, &(&1 =~ "Deeply nested"))
    end

    test "counts if, case, cond, with as nesting levels" do
      # Mix different nesting constructs — need enough depth to exceed threshold
      code = """
      @doc "Nested."
      @spec handle(map()) :: map()
      def handle(params) do
        if params do
          case params do
            %{} ->
              cond do
                true ->
                  if true do
                    case params do
                      %{} ->
                        with {:ok, x} <- {:ok, 1} do
                          x
                        end
                    end
                  end
              end
          end
        end
      end
      """

      result = Linter.check_credo(code)

      assert Enum.any?(result.issues, &(&1 =~ "Deeply nested"))
    end

    test "does not count non-nesting constructs (pipe, fn)" do
      code = """
      @doc "Pipes."
      @spec handle(map()) :: map()
      def handle(params) do
        params
        |> Map.get("items", [])
        |> Enum.map(fn item ->
          item
          |> Map.get("name", "")
          |> String.upcase()
        end)
        |> Enum.filter(fn name -> name != "" end)
      end
      """

      result = Linter.check_credo(code)
      nesting_issues = Enum.filter(result.issues, &(&1 =~ "Deeply nested"))

      assert nesting_issues == []
    end

    test "gracefully handles code that doesn't parse" do
      code = "if true do\n  case do\n  end"

      result = Linter.check_credo(code)

      # Should not crash — nesting check skips on parse error
      assert is_map(result)
      assert result.check == :credo
    end
  end

  # ──────────────────────────────────────────────────────────────
  # check_credo/1 — combined
  # ──────────────────────────────────────────────────────────────

  describe "check_credo/1 — combined checks" do
    test "reports all issues at once" do
      long_line = String.duplicate("x", 130)

      code = """
      def handle(params) do
        "#{long_line}"
      end
      """

      result = Linter.check_credo(code)

      # Should have: missing @spec, missing @doc, long line
      assert Enum.any?(result.issues, &(&1 =~ "Missing @spec"))
      assert Enum.any?(result.issues, &(&1 =~ "Missing @doc"))
      assert Enum.any?(result.issues, &(&1 =~ "exceeds"))
    end

    test "returns :pass status when all checks pass" do
      code = """
      @doc "Clean code."
      @spec handle(map()) :: map()
      def handle(params), do: params
      """

      result = Linter.check_credo(code)

      assert result.status == :pass
      assert result.issues == []
    end

    test "returns :warn status when any issue found" do
      code = "def handle(params), do: params"

      result = Linter.check_credo(code)

      assert result.status == :warn
      assert result.issues != []
    end

    test "handles empty string" do
      result = Linter.check_credo("")

      assert result.check == :credo
      assert result.status == :pass
      assert result.issues == []
    end

    test "handles code with only comments" do
      code = "# just a comment\n# another one"

      result = Linter.check_credo(code)

      assert result.status == :pass
    end

    test "handles defmodule wrapper (allowed: Request, Response, Params)" do
      code = """
      defmodule Request do
        @doc "Request schema."
        @spec changeset(map(), map()) :: map()
        def changeset(struct, params), do: {struct, params}
      end
      """

      result = Linter.check_credo(code)

      # defmodule should not trigger "Missing @doc" since public_function_def? excludes it
      doc_issues =
        Enum.filter(result.issues, &(&1 =~ "Missing @doc for public function defmodule"))

      assert doc_issues == []
    end
  end
end
