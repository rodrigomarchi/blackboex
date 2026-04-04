defmodule Blackboex.Testing.SandboxCase do
  @moduledoc """
  Lightweight test case module that provides the `test` macro and assertions
  without registering with ExUnit.Server. Used by TestRunner to compile
  user-generated test code without leaking modules into the global ExUnit runner.

  Code injection is prevented by the TestRunner's AST replacement step before
  compilation: `use ExUnit.Case` is replaced with `use Blackboex.Testing.SandboxCase`.
  """

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import ExUnit.Assertions
      import Blackboex.Testing.SandboxCase, only: [test: 2, describe: 2]
    end
  end

  @doc """
  Defines a test function. Like ExUnit.Case.test/2 but without
  ExUnit registration. Each test becomes a function named `test <name>/1`.
  """
  @spec test(String.t(), keyword()) :: Macro.t()
  defmacro test(name, do: block) do
    fun_name = :"test #{name}"

    quote do
      def unquote(fun_name)(_context) do
        unquote(block)
      end
    end
  end

  @doc """
  Groups tests under a description. Compatible with ExUnit.Case.describe/2.
  In sandbox mode, the block is simply executed (no ExUnit grouping needed).
  """
  @spec describe(String.t(), keyword()) :: Macro.t()
  defmacro describe(_message, do: block) do
    block
  end
end
