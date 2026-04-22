defmodule Blackboex.PageAgent.ContentParser do
  @moduledoc """
  Extracts markdown content and an optional summary from an LLM response.

  Uses tilde fences (`~~~markdown` / `~~~md` / `~~~`) by default so that
  nested backtick code blocks (```` ```elixir ````) inside the page content
  are preserved. A `~~~markdown` opener is non-ambiguous and CommonMark-
  compliant for nesting. A backtick fence `~~~markdown` fallback covers LLMs
  that default to backticks anyway.

  Expected shape:

      ~~~markdown
      # page content
      ```elixir
      inner code block
      ```
      ~~~

      Resumo: breve descrição opcional.
  """

  @summary_max 200
  @default_summary "Conteúdo atualizado pelo agente"

  @tilde_fence ~r/~~~(?:markdown|md)?\s*\n(.*?)\n~~~/s
  @backtick_fence ~r/```(?:markdown|md)\s*\n(.*?)\n```/s
  @summary_line ~r/^\s*Resumo:\s*(.+)$/m

  @spec extract_content(String.t()) :: {:ok, String.t()} | {:error, :no_content_block}
  def extract_content(content) when is_binary(content) do
    normalized = normalize_newlines(content)

    cond do
      match = Regex.run(@tilde_fence, normalized) ->
        [_, body] = match
        {:ok, String.trim(body)}

      match = Regex.run(@backtick_fence, normalized) ->
        [_, body] = match
        {:ok, String.trim(body)}

      true ->
        {:error, :no_content_block}
    end
  end

  @spec extract_summary(String.t()) :: String.t()
  def extract_summary(content) when is_binary(content) do
    case Regex.run(@summary_line, content) do
      [_, summary] -> summary |> String.trim() |> truncate()
      nil -> @default_summary
    end
  end

  defp normalize_newlines(str), do: String.replace(str, "\r\n", "\n")

  defp truncate(text) do
    if String.length(text) > @summary_max do
      String.slice(text, 0, @summary_max) <> "…"
    else
      text
    end
  end
end
