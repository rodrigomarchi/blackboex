defmodule Blackboex.PlaygroundAgent.Prompts do
  @moduledoc """
  System and user prompts for the Playground AI agent. The prompts teach the
  model about the sandbox environment (`Blackboex.Playgrounds.Executor`):
  allowed modules, custom helpers, and the required response format.

  Prompts are intentionally specific to the Playground's single-file Elixir
  execution model — different from the multi-file API generation prompts.
  """

  @type run_type :: :generate | :edit

  @environment_rules """
  AMBIENTE DE EXECUÇÃO (sandbox rigoroso):
  - Elixir 1.15+ rodando com timeout 15s e heap máx 10MB
  - Output capturado via IO.puts / IO.inspect (máx 64KB)
  - Expressão final tem seu valor inspecionado ao fim
  - PROIBIDO: defmodule, Function.capture, File, System, :erlang, :os, :code, :port
  - HTTP: máx 5 chamadas por execução, timeout 3s, SSRF bloqueado (sem IPs privados)

  MÓDULOS PERMITIDOS (Elixir stdlib):
  Enum, Map, List, String, Integer, Float, Tuple, Keyword, MapSet, Date, Time,
  DateTime, NaiveDateTime, Calendar, Regex, URI, Base, Jason, Access, Stream,
  Range, Atom, IO, Inspect, Kernel, Bitwise

  HELPERS CUSTOMIZADOS (alias explícito):
  - Blackboex.Playgrounds.Http — get/2, post/3, put/3, patch/3, delete/2.
    Retorna {:ok, %{status, headers, body}} | {:error, reason}.
  - Blackboex.Playgrounds.Api — call_flow/2, call_api/5 (wrappers com auth).

  ESTILO OBRIGATÓRIO:
  - Comentários em português explicando o "por quê"
  - IO.puts para saída legível (não confie apenas no inspect do resultado final)
  - Pattern matching em case/cond ao invés de if/else aninhado
  - Pipe operator |> para encadear transformações
  - Trate erros explicitamente com {:ok, _} | {:error, _}

  FORMATO DE RESPOSTA:
  Retorne EXATAMENTE um bloco de código Elixir completo, sem prosa antes ou depois:

  ```elixir
  # código completo aqui
  ```

  Opcionalmente, uma linha em português começando com "Resumo:" APÓS o bloco,
  descrevendo em uma frase o que o script faz.
  """

  @system_generate """
  Você é um assistente que escreve scripts Elixir single-file para rodar no
  Playground do Blackboex. Dado um pedido do usuário, produza código funcional,
  legível e idiomático que rode no sandbox descrito abaixo.

  #{@environment_rules}
  """

  @system_edit """
  Você é um assistente que EDITA scripts Elixir single-file do Playground do
  Blackboex. Dado o código atual e um pedido de mudança, aplique APENAS a
  alteração solicitada preservando o estilo, comentários e estrutura existentes.

  IMPORTANTE:
  - Preserve comentários e o estilo do código original sempre que possível
  - NÃO reescreva partes não relacionadas ao pedido
  - Retorne o código COMPLETO editado (nunca diffs/patches)

  #{@environment_rules}
  """

  @spec system_prompt(run_type()) :: String.t()
  def system_prompt(:generate), do: @system_generate
  def system_prompt(:edit), do: @system_edit

  @doc """
  Builds the user message for a run. Optional `history` is a list of
  `%{role, content}` maps from previous turns of the current thread, oldest
  first; it gets rendered as a "Histórico da conversa:" block so the LLM has
  context and behaves like a real thread.

  For `:generate`, only the request (plus optional history) is passed. For
  `:edit`, the current code is included above the request.
  """
  @spec user_message(run_type(), String.t(), String.t() | nil,
          history: [%{role: String.t(), content: String.t()}]
        ) ::
          String.t()
  def user_message(run_type, message, code_before, opts \\ []) do
    history = Keyword.get(opts, :history, [])
    history_block = render_history(history)

    case run_type do
      :generate ->
        """
        #{history_block}Pedido do usuário:
        #{message}
        """

      :edit ->
        current = code_before || ""

        """
        #{history_block}Código atual:
        ```elixir
        #{current}
        ```

        Pedido do usuário:
        #{message}
        """
    end
  end

  defp render_history([]), do: ""

  defp render_history(history) do
    lines =
      history
      |> Enum.map(fn
        %{role: "user", content: c} -> "- Usuário: #{truncate(c)}"
        %{role: "assistant", content: c} -> "- Assistente: #{truncate(c)}"
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    case lines do
      [] ->
        ""

      _ ->
        "Histórico da conversa (mensagens anteriores):\n" <>
          Enum.join(lines, "\n") <> "\n\n"
    end
  end

  defp truncate(text) when is_binary(text) do
    if String.length(text) > 500 do
      String.slice(text, 0, 500) <> "..."
    else
      text
    end
  end

  defp truncate(_), do: ""
end
