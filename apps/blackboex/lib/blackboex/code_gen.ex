defmodule Blackboex.CodeGen do
  @moduledoc """
  The CodeGen context. Provides code generation infrastructure:
  compilation, linting, AST validation, sandboxed execution, and diff operations.
  """

  defdelegate compile(api, code), to: Blackboex.CodeGen.Compiler
  defdelegate compile_files(api, files), to: Blackboex.CodeGen.Compiler
  defdelegate validate_ast(code), to: Blackboex.CodeGen.ASTValidator, as: :validate
  defdelegate lint(code), to: Blackboex.CodeGen.Linter, as: :run_all
  defdelegate auto_format(code), to: Blackboex.CodeGen.Linter
  defdelegate execute_plug(module, conn, opts), to: Blackboex.CodeGen.Sandbox
  defdelegate compute_diff(old, new), to: Blackboex.CodeGen.DiffEngine
  defdelegate format_diff_summary(diff), to: Blackboex.CodeGen.DiffEngine
  defdelegate apply_search_replace(code, blocks), to: Blackboex.CodeGen.DiffEngine
end
