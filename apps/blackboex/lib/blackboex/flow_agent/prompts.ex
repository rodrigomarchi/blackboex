defmodule Blackboex.FlowAgent.Prompts do
  @moduledoc """
  System and user prompts for the FlowAgent. Teaches the LLM the canonical
  `BlackboexFlow` JSON schema, lists every node type with its `data` fields,
  and injects three real templates as few-shot examples.

  Output contract enforced by `DefinitionParser`:

      ~~~json
      {"version":"1.0","nodes":[...],"edges":[...]}
      ~~~

  Optionally followed by a single `Resumo:` line.
  """

  alias Blackboex.FlowAgent.Prompts.Examples

  @type run_type :: :generate | :edit

  @max_history_chars 500
  # Unicode zero-width space used to neutralize user-supplied fence openers.
  @zwsp "\u200B"

  @structural_contract """
  CONTRATO ESTRUTURAL (validado antes de salvar):
  - version = "1.0"
  - nodes: lista de objetos com campos id, type, position:{x,y}, data
  - ids de nó no formato "n1", "n2", "n3"…  (regex: ^n\\d+$)
  - edges: lista de objetos com id, source, source_port (int), target, target_port (int)
  - Exatamente UM nó do tipo "start"; pelo menos um nó "end"
  - Sem ciclos; sem fan-in (cada porta de destino recebe no máximo 1 aresta)
  - Sem self-loops; sem arestas duplicadas (mesmo par source_port → target_port)
  - source_port respeita os outputs fixos do tipo (condition é dinâmico; demais fixos em 1)
  """

  @node_catalog """
  TIPOS DE NÓ (campos de data):

  - start: execution_mode ("sync"|"async"), timeout (ms), payload_schema [],
    state_schema []. Schemas são listas de {name, type, required, constraints,
    initial_value}. Type ∈ {string, integer, float, boolean, array, object}.

  - elixir_code: code (string Elixir que retorna tupla {output, new_state}).
    Timeout opcional via timeout_ms.

  - condition: expression (Elixir que retorna int 0..N — porta de saída),
    branch_labels (mapa {"0": "Sim", "1": "Não"} para legendas no canvas).

  - end: response_schema [], response_mapping [{response_field, state_variable}].

  - http_request: method ("GET"|"POST"|"PUT"|"PATCH"|"DELETE"),
    url (aceita {{state.X}} e {{input.X}}), headers (map), body_template (string),
    timeout_ms, max_retries, expected_status [], auth_type, auth_config.

  - delay: duration_ms, max_duration_ms.

  - for_each: source_expression (Elixir que retorna lista), body_code (Elixir),
    item_variable ("item"), accumulator (nome do campo em state).

  - webhook_wait: event_type (string), timeout_ms, resume_path (opcional).

  - sub_flow: flow_id (UUID de outro flow ativo), input_mapping {...},
    timeout_ms (opcional).

  - fail: message (string), include_state (boolean).

  - debug: expression (Elixir), log_level ("info"|"warn"|"error"), state_key.
  """

  @output_format """
  DOIS MODOS DE OPERAÇÃO (você escolhe com base no pedido):

  1. MODO EDIÇÃO — quando o pedido é para CRIAR, MODIFICAR, ADICIONAR,
     REMOVER, CONECTAR ou REFATORAR o fluxo. Produza a definição COMPLETA:

     ~~~json
     {"version":"1.0","nodes":[...],"edges":[...]}
     ~~~

     Opcionalmente, uma linha "Resumo: ..." APÓS o bloco descrevendo em uma
     frase o que você fez.

  2. MODO EXPLICAÇÃO — quando o pedido é para EXPLICAR, DESCREVER,
     RESUMIR, ANALISAR ou TIRAR DÚVIDA sobre o fluxo atual (ex.: "me explica
     como funciona", "pra que serve esse nó", "como esse condicional
     decide"). NÃO emita bloco JSON. Responda em markdown simples começando
     obrigatoriamente com `Resposta:`:

     ```
     Resposta: <sua explicação em português, pode usar listas e headings>
     ```

     Nesse modo o fluxo NÃO é modificado — você só conversa sobre ele.

  REGRA DE OURO: em caso de dúvida, se o usuário não usou verbos de ação
  (criar, adicionar, remover, editar…), prefira o modo explicação. Jamais
  altere o fluxo sem intenção clara do usuário.

  POSICIONAMENTO (modo edição apenas):
  - Distribua os nodes em colunas (x += 200) por profundidade topológica
  - E em linhas (y += 150) por ramo (útil em condition com múltiplas saídas)
  - Se omitir `position`, um auto-layout será aplicado
  """

  @few_shot Examples.few_shot_json()

  @system_generate """
  Você é um assistente que PROJETA fluxos executáveis no Blackboex. Dado um
  pedido do usuário, produza a definição canônica completa do fluxo em JSON.

  #{@structural_contract}

  #{@node_catalog}

  #{@output_format}

  EXEMPLOS REAIS (use como referência de estilo e estrutura):

  #{@few_shot}
  """

  @system_edit """
  Você é um assistente que EDITA fluxos executáveis do Blackboex. Dado o
  fluxo atual e um pedido de mudança, aplique APENAS a alteração solicitada
  preservando todos os outros nodes, edges e posições que não precisam mudar.

  IMPORTANTE:
  - Preserve nodes, edges, posições e configs que não se relacionam ao pedido
  - NÃO reescreva o fluxo inteiro por pura estética
  - Retorne a definição COMPLETA editada (nunca diffs/patches)
  - Mantenha os IDs existentes; adicione novos apenas para nodes inéditos

  #{@structural_contract}

  #{@node_catalog}

  #{@output_format}

  EXEMPLOS REAIS (use como referência de estilo e estrutura):

  #{@few_shot}
  """

  @spec system_prompt(run_type()) :: String.t()
  def system_prompt(:generate), do: @system_generate
  def system_prompt(:edit), do: @system_edit

  @doc """
  Builds the user message for a run. For `:generate`, only the request is
  passed (plus optional history). For `:edit`, the current definition is
  included above the request inside a `~~~json` fence.

  Options:

    * `:history` — list of `%{role, content}` maps from previous turns of the
      current thread, oldest-first. Rendered as "Histórico da conversa:" so
      the LLM behaves like a real thread instead of a one-shot.
  """
  @spec user_message(run_type(), String.t(), map() | nil,
          history: [%{role: String.t(), content: String.t()}]
        ) ::
          String.t()
  def user_message(run_type, message, definition_before, opts \\ [])

  def user_message(run_type, message, definition_before, opts) when is_list(opts) do
    history = Keyword.get(opts, :history, [])
    build_user_message(run_type, message, definition_before, history)
  end

  def user_message(run_type, message, definition_before, %{} = attrs) do
    user_message(run_type, message, definition_before, Enum.into(attrs, []))
  end

  defp build_user_message(:generate, message, _definition_before, history) do
    """
    #{render_history(history)}Pedido do usuário:
    #{sanitize(message)}
    """
  end

  defp build_user_message(:edit, message, definition_before, history) do
    current_json = serialize_definition(definition_before)

    """
    #{render_history(history)}Definição atual do fluxo:
    ~~~json
    #{current_json}
    ~~~

    Pedido do usuário:
    #{sanitize(message)}
    """
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
      [] -> ""
      _ -> "Histórico da conversa (mensagens anteriores):\n" <> Enum.join(lines, "\n") <> "\n\n"
    end
  end

  defp truncate(text) when is_binary(text) do
    if String.length(text) > @max_history_chars do
      String.slice(text, 0, @max_history_chars) <> "..."
    else
      text
    end
  end

  defp truncate(_), do: ""

  # Defensive: if the user message starts lines with `~~~` the LLM could be
  # tricked into closing our fence early. Prepend a zero-width space to any
  # leading triple-tilde/triple-backtick sequence so the neutralized version
  # is no longer a valid markdown fence.
  defp sanitize(message) when is_binary(message) do
    message
    |> String.replace(~r/(^|\n)(~~~|```)/, "\\1" <> @zwsp <> "\\2")
  end

  defp sanitize(_), do: ""

  defp serialize_definition(nil), do: "{}"
  defp serialize_definition(definition) when is_map(definition), do: Jason.encode!(definition)
  defp serialize_definition(_), do: "{}"
end
