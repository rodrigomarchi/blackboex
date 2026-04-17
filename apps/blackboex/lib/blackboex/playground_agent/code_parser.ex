defmodule Blackboex.PlaygroundAgent.CodeParser do
  @moduledoc """
  Extracts Elixir source code and an optional summary from an LLM response.

  Expected response shape:

      ```elixir
      # generated code
      ```

      Resumo: breve descrição opcional.
  """

  @elixir_fence ~r/```(?:elixir|ex)\s*\n(.*?)\n```/s
  @any_fence ~r/```\s*\n(.*?)\n```/s
  @summary_line ~r/^\s*Resumo:\s*(.+)$/m

  @spec extract_code(String.t()) :: {:ok, String.t()} | {:error, :no_code_block}
  def extract_code(content) when is_binary(content) do
    cond do
      match = Regex.run(@elixir_fence, content) ->
        [_, code] = match
        {:ok, String.trim(code)}

      match = Regex.run(@any_fence, content) ->
        [_, code] = match
        {:ok, String.trim(code)}

      true ->
        {:error, :no_code_block}
    end
  end

  @spec extract_summary(String.t()) :: String.t()
  def extract_summary(content) when is_binary(content) do
    case Regex.run(@summary_line, content) do
      [_, summary] -> String.trim(summary)
      nil -> "Código gerado pelo agente"
    end
  end
end
