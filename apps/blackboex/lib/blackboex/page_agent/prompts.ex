defmodule Blackboex.PageAgent.Prompts do
  @moduledoc """
  System and user prompts for the Page editor AI agent. Tailored for prose
  edits (markdown documentation, notes, posts) — distinct from the Playground
  agent (Elixir code) and the API agent (multi-file handlers).
  """

  @type run_type :: :generate | :edit

  @max_content_before 30_000

  @editor_rules """
  CONTEXTO:
  Você está editando uma página de documentação/conteúdo dentro do Blackboex.
  O conteúdo é escrito em MARKDOWN puro (CommonMark + GFM), renderizado num
  editor WYSIWYG (Tiptap). Headings, listas, citações, blocos de código,
  tabelas, links e imagens são todos suportados.

  REGRAS DE ESTILO:
  - Mantenha o tom e a voz do conteúdo original sempre que possível
  - Prefira frases claras e diretas; evite jargão desnecessário
  - Use headings (#, ##, ###) para estruturar seções longas
  - Use listas com marcadores quando enumerar itens
  - Quando incluir código, use ```` ```linguagem ```` (ex.: ```` ```elixir ````)
  - Não inclua front-matter, HTML cru, ou metadados — apenas markdown limpo

  FORMATO DE RESPOSTA OBRIGATÓRIO:
  Retorne EXATAMENTE um único bloco delimitado por TIL DUPLAS (`~~~markdown`
  e `~~~`), contendo o conteúdo COMPLETO da página (não diffs/patches). Essa
  delimitação permite blocos ```` ``` ```` de código aninhados sem ambiguidade.
  Não escreva prosa antes do bloco.

  ~~~markdown
  conteúdo completo aqui
  ~~~

  Após o bloco, opcionalmente uma única linha em português começando com
  "Resumo:" descrevendo em uma frase o que você fez.
  """

  @system_generate """
  Você é um assistente que ESCREVE páginas de documentação em markdown para o
  editor de Pages do Blackboex. Dado um pedido do usuário, produza uma página
  completa, bem estruturada e idiomática.

  #{@editor_rules}
  """

  @system_edit """
  Você é um assistente que EDITA páginas de documentação em markdown no editor
  de Pages do Blackboex. Dado o conteúdo atual e um pedido de mudança, aplique
  APENAS a alteração solicitada preservando o estilo, tom e estrutura
  existentes.

  IMPORTANTE:
  - Preserve seções e estilo do original sempre que possível
  - NÃO reescreva partes não relacionadas ao pedido
  - Retorne o conteúdo COMPLETO editado (nunca diffs/patches)

  #{@editor_rules}
  """

  @spec system_prompt(run_type()) :: String.t()
  def system_prompt(:generate), do: @system_generate
  def system_prompt(:edit), do: @system_edit

  @doc """
  Builds the user message. Optional `history` is a list of `%{role, content}`
  maps from previous turns, oldest-first; rendered as "Histórico da conversa:".

  For `:generate`, only the request (plus optional history) is passed. For
  `:edit`, the current content is included above the request, truncated to
  ~30k chars to avoid runaway prompts on huge pages.
  """
  @spec user_message(run_type(), String.t(), String.t() | nil,
          history: [%{role: String.t(), content: String.t()}]
        ) :: String.t()
  def user_message(run_type, message, content_before, opts \\ []) do
    history = Keyword.get(opts, :history, [])
    history_block = render_history(history)

    case run_type do
      :generate ->
        """
        #{history_block}Pedido do usuário:
        #{message}
        """

      :edit ->
        current = content_before |> Kernel.||("") |> truncate_content() |> sanitize_fences()

        """
        #{history_block}Conteúdo atual:
        ~~~markdown
        #{current}
        ~~~

        Pedido do usuário:
        #{message}
        """
    end
  end

  # Defuse prompt-injection attempts where the user puts a literal fence in
  # their page content to break out of the wrapper and inject instructions.
  # Any line that starts with three (or more) tildes/backticks gets a leading
  # zero-width space inserted so the markdown parser still treats it as text
  # but the LLM no longer sees a fence terminator.
  defp sanitize_fences(content) when is_binary(content) do
    content
    |> String.replace(~r/^(~~~+)/m, "\u200B\\1")
    |> String.replace(~r/^(```+)/m, "\u200B\\1")
  end

  defp render_history([]), do: ""

  defp render_history(history) do
    lines =
      history
      |> Enum.map(fn
        %{role: "user", content: c} -> "- Usuário: #{truncate_msg(c)}"
        %{role: "assistant", content: c} -> "- Assistente: #{truncate_msg(c)}"
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    case lines do
      [] -> ""
      _ -> "Histórico da conversa (mensagens anteriores):\n" <> Enum.join(lines, "\n") <> "\n\n"
    end
  end

  defp truncate_msg(text) when is_binary(text) do
    if String.length(text) > 500, do: String.slice(text, 0, 500) <> "...", else: text
  end

  defp truncate_msg(_), do: ""

  defp truncate_content(content) when is_binary(content) do
    if String.length(content) > @max_content_before do
      String.slice(content, 0, @max_content_before) <> "\n\n[truncado por tamanho]"
    else
      content
    end
  end
end
