# Prompt: Completar Integração do Agent Pipeline V2

## Contexto do Projeto

BlackBoex é uma plataforma de criação de APIs via linguagem natural. O usuário descreve uma API, um LLM gera código Elixir, e a plataforma compila, testa, valida e publica como endpoint HTTP real.

O projeto é um umbrella Elixir/Phoenix com dois apps:
- `apps/blackboex/` — domínio (LLM, code gen, billing, testes, analytics)
- `apps/blackboex_web/` — web (LiveView IDE, router dinâmico, admin Backpex)

### O que já existe (Pipeline V1 — antigo, ainda ativo)

O pipeline antigo usa:
- `Blackboex.CodeGen.GenerationWorker` — Oban worker que gera código via LLM
- `Blackboex.CodeGen.UnifiedPipeline` — módulo monolítico de ~500 linhas que formata, compila, lint, testa em sequência com retry manual
- `Blackboex.Apis.Conversations` — contexto que armazena chat como JSONB array na tabela `api_conversations`
- `Blackboex.Apis.ApiConversation` — schema com campo `messages` (JSONB array de `{role, content, timestamp}`)

O LiveView `edit.ex` chama diretamente:
- `UnifiedPipeline.generate_edit_only/5` via `Task.async` para edições via chat
- `UnifiedPipeline.validate_and_test/3` via `Task.async` para validação
- `UnifiedPipeline.validate_on_save/3` via `Task.async` para salvar
- `Conversations.append_message/4` para persistir mensagens no JSONB
- PubSub topic `"api:#{api_id}"` com mensagens como `{:generation_token, token}`, `{:generation_complete, result}`

### O que foi construído (Pipeline V2 — novo, NÃO integrado ao frontend)

O novo pipeline é agentic — o LLM tem tools (compile, format, lint, test, submit) e decide autonomamente a ordem das operações. Usa LangChain Elixir como camada de orquestração LLM.

**Módulos novos criados:**

| Arquivo | Descrição |
|---------|-----------|
| `lib/blackboex/conversations/conversation.ex` | Schema Ecto — container 1:1 com API, stats agregadas |
| `lib/blackboex/conversations/run.ex` | Schema Ecto — execução do agente (generation/edit), métricas, resultado final |
| `lib/blackboex/conversations/event.ex` | Schema Ecto — cada ação atômica (message, tool_call, tool_result, guardrail, etc.) |
| `lib/blackboex/conversations.ex` | Contexto CRUD para conversations, runs, events |
| `lib/blackboex/agent/tools.ex` | 6 LangChain Function tools (compile_code, format_code, lint_code, generate_tests, run_tests, submit_code) |
| `lib/blackboex/agent/guardrails.ex` | Limites: max iterations, cost, time, loop detection |
| `lib/blackboex/agent/callbacks.ex` | LangChain callbacks → persist Event no DB + PubSub broadcast |
| `lib/blackboex/agent/context_builder.ex` | Monta resumos de runs anteriores para contexto inter-run |
| `lib/blackboex/agent/code_gen_chain.ex` | LLMChain para geração inicial (system prompt + tools) |
| `lib/blackboex/agent/edit_chain.ex` | LLMChain para edição via chat (contexto de runs anteriores + código atual) |
| `lib/blackboex/agent/session.ex` | GenServer per run — monta chain, roda em Task, persiste events, guardrails, emite PubSub |
| `lib/blackboex/agent/kickoff_worker.ex` | Oban worker — cria Conversation/Run/Event, inicia Session GenServer |
| `lib/blackboex/agent/recovery_worker.ex` | Oban cron (2min) — detecta runs stale, marca como failed |
| `lib/blackboex/llm/circuit_breaker.ex` | GenServer per provider (closed/open/half_open) |

**Tabelas DB criadas (migration `20260327133937_create_conversations.exs`):**
- `conversations` (id, api_id, organization_id, title, status, stats)
- `runs` (id, conversation_id, api_id, user_id, run_type, status, trigger_message, config, final_code/test_code/doc, metrics, timing)
- `events` (id, run_id, conversation_id, event_type, sequence, role, content, tool_name/input/output/success/duration, code_snapshot, tokens, metadata)

**Feature flag:** `:agent_pipeline` via FunWithFlags. `KickoffWorker` checa essa flag antes de executar.

**Funções públicas adicionadas em `Blackboex.Apis`:**
- `start_agent_generation/3` — enfileira KickoffWorker com run_type "generation"
- `start_agent_edit/3` — enfileira KickoffWorker com run_type "edit"
- `agent_pipeline_enabled?/0` — checa feature flag

**PubSub messages emitidas pelo novo agent (topic `"run:#{run_id}"` e `"api:#{api_id}"`):**
```elixir
{:agent_run_started, %{run_id: id, run_type: type}}        # via KickoffWorker, topic api:id
{:agent_started, %{run_id: id, run_type: type}}             # via Session, topic run:id
{:agent_streaming, %{delta: string, run_id: id}}            # via Callbacks, topic run:id
{:agent_message, %{role: string, content: string, run_id: id}} # via Callbacks, topic run:id
{:agent_action, %{tool: name, run_id: id}}                  # via Callbacks, topic run:id
{:tool_started, %{tool: name, run_id: id}}                  # via Callbacks, topic run:id
{:tool_result, %{tool: name, success: bool, summary: string, run_id: id}} # via Callbacks, topic run:id
{:guardrail_triggered, %{type: atom, run_id: id}}           # via Callbacks, topic run:id
{:agent_completed, %{code: string, test_code: string, summary: string, run_id: id, status: string}} # via Session, topic run:id
{:agent_failed, %{error: string, run_id: id}}               # via Session, topic run:id e api:id
```

**Estado atual:** Tudo compila, 269 testes passam, zero warnings, zero issues Credo nos novos módulos. Mas o frontend NÃO está conectado ao novo pipeline.

---

## O Que Falta: Task List Completa

### TASK 1: Reescrever `handle_event("send_chat")` em edit.ex

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas atuais:** 1622-1637

**Comportamento atual:**
```elixir
def handle_event("send_chat", %{"chat_input" => message}, socket) do
  conversation = socket.assigns.chat_conversation
  case Conversations.append_message(conversation, "user", message) do
    {:ok, conversation} ->
      do_chat_request(socket, conversation, message)
    {:error, :too_many_messages} ->
      {:noreply, put_flash(socket, :error, "...")}
  end
end
```
Chama `Conversations.append_message` (JSONB) e depois `do_chat_request` que chama `UnifiedPipeline.generate_edit_only` via `Task.async`.

**Comportamento necessário:**
1. Checar `Apis.agent_pipeline_enabled?()` para decidir qual pipeline usar
2. Se agent: chamar `Apis.start_agent_edit(api, message, user_id)`
3. Subscribir no PubSub topic `"run:#{run_id}"` (o run_id será recebido via `{:agent_run_started}`)
4. Atualizar assigns: `chat_loading: true`, `chat_input: ""`, adicionar mensagem do user na lista local
5. NÃO chamar `Task.async` — o Oban job cuida de tudo
6. Se pipeline antigo: manter comportamento atual (para rollback via flag)

**Contexto adicional:** O `do_chat_request/3` (linhas 2354-2364) checa billing limit antes de chamar `do_chat_llm_call`. Essa checagem deve ser mantida no novo fluxo também — fazer antes de enfileirar o job.

---

### TASK 2: Reescrever `do_chat_llm_call` em edit.ex

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas atuais:** 2366-2391

**Comportamento atual:**
```elixir
defp do_chat_llm_call(socket, conversation, message) do
  task = Task.async(fn ->
    UnifiedPipeline.generate_edit_only(api, code, message, conversation.messages,
      progress_callback: fn progress -> send(lv_pid, {:pipeline_progress, progress}) end,
      token_callback: fn token -> send(lv_pid, {:llm_token, token}) end
    )
  end)
  {:noreply, assign(socket, pipeline_ref: task.ref)}
end
```

**Comportamento necessário (agent):**
- Não precisa mais de `Task.async` — o KickoffWorker cria o run e o Session roda a chain
- O LiveView subscribe no PubSub e recebe events
- O `pipeline_ref` não é mais necessário — substituir por `current_run_id`
- As mensagens `{:llm_token}` e `{:pipeline_progress}` são substituídas por `{:agent_streaming}`, `{:agent_action}`, `{:tool_result}`

---

### TASK 3: Adicionar novo assign `current_run_id` e subscription dinâmica

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas atuais:** Mount (41-139)

**O que precisa:**
1. Novo assign `current_run_id: nil` no mount
2. Quando receber `{:agent_run_started, %{run_id: run_id}}` no topic `"api:#{api_id}"`:
   - Salvar `current_run_id` no assign
   - Subscribe no topic `"run:#{run_id}"` para receber events do agent
3. Na reconexão (mount), checar se há um run ativo:
   ```elixir
   active_run = Conversations.list_runs(conversation.id, limit: 1)
                |> Enum.find(&(&1.status == "running"))
   if active_run, do: subscribe("run:#{active_run.id}")
   ```

---

### TASK 4: Criar handlers para mensagens do novo agent

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`

**Handlers necessários (TODOS novos):**

```elixir
# Agent começou (recebido no topic api:id)
def handle_info({:agent_run_started, %{run_id: run_id, run_type: _type}}, socket) do
  Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")
  {:noreply, assign(socket, current_run_id: run_id, chat_loading: true)}
end

# Agent streaming tokens (recebido no topic run:id)
def handle_info({:agent_streaming, %{delta: delta}}, socket) do
  new_tokens = socket.assigns.streaming_tokens <> delta
  {:noreply, assign(socket, streaming_tokens: new_tokens)}
end

# Agent chamou uma tool
def handle_info({:agent_action, %{tool: tool_name}}, socket) do
  {:noreply, assign(socket, pipeline_status: tool_to_status(tool_name))}
end

# Tool executou (para timeline de progresso)
def handle_info({:tool_started, %{tool: tool_name}}, socket) do
  {:noreply, assign(socket, pipeline_status: tool_to_status(tool_name))}
end

# Tool completou
def handle_info({:tool_result, %{tool: tool_name, success: success, summary: summary}}, socket) do
  # Adicionar à timeline de eventos visível ao user
  event = %{tool: tool_name, success: success, summary: summary}
  {:noreply, update(socket, :agent_events, &[event | &1])}
end

# Guardrail disparou
def handle_info({:guardrail_triggered, %{type: type}}, socket) do
  {:noreply, put_flash(socket, :warning, "Agent limit reached: #{type}")}
end

# Agent completou com sucesso
def handle_info({:agent_completed, %{code: code, test_code: test_code, summary: summary, run_id: run_id}}, socket) do
  api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)
  {:noreply,
   socket
   |> assign(
     api: api,
     code: code || socket.assigns.code,
     test_code: test_code || socket.assigns.test_code,
     chat_loading: false,
     current_run_id: nil,
     streaming_tokens: "",
     pipeline_status: nil
   )
   |> push_editor_value(code || socket.assigns.code)
   |> put_flash(:info, summary || "Code updated successfully")}
end

# Agent falhou
def handle_info({:agent_failed, %{error: error, run_id: _run_id}}, socket) do
  {:noreply,
   socket
   |> assign(chat_loading: false, current_run_id: nil, pipeline_status: nil)
   |> put_flash(:error, "Agent failed: #{error}")}
end

# Mensagem do agent (thinking/reasoning)
def handle_info({:agent_message, %{role: "assistant", content: content}}, socket) do
  # Adicionar à timeline visível ao user
  {:noreply, update(socket, :agent_events, &[%{type: :message, content: content} | &1])}
end
```

**Helper necessário:**
```elixir
defp tool_to_status("compile_code"), do: :compiling
defp tool_to_status("format_code"), do: :formatting
defp tool_to_status("lint_code"), do: :linting
defp tool_to_status("generate_tests"), do: :generating_tests
defp tool_to_status("run_tests"), do: :running_tests
defp tool_to_status("submit_code"), do: :submitting
defp tool_to_status(_), do: :processing
```

---

### TASK 5: Carregar chat history dos events (não do JSONB)

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas atuais:** 76 (`chat_messages: conversation.messages`)

**Comportamento atual:** `conversation.messages` é um JSONB array `[{role, content, ...}]`

**Comportamento necessário:**
```elixir
# No mount, carregar conversation e eventos de mensagens:
{:ok, conversation} = Blackboex.Conversations.get_or_create_conversation(api.id, org.id)

chat_messages =
  if conversation.total_events > 0 do
    Blackboex.Conversations.list_events(last_run_id)
    |> Enum.filter(&(&1.event_type in ["user_message", "assistant_message"]))
    |> Enum.map(fn e -> %{"role" => e.role, "content" => e.content} end)
  else
    # Fallback: load from old api_conversations if exists (migration period)
    old_conv = Blackboex.Apis.Conversations.get_or_create_conversation(api.id)
    old_conv.messages
  end
```

**Novo assign necessário:**
```elixir
conversation: conversation,  # Blackboex.Conversations.Conversation (novo)
chat_messages: chat_messages, # lista de maps %{role, content}
current_run_id: nil,
agent_events: [],  # timeline de ações do agent (tool calls, results, messages)
```

---

### TASK 6: Reescrever `maybe_enqueue_generation` em index.ex

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/index.ex`
**Linhas atuais:** 153-161

**Comportamento atual:**
```elixir
alias Blackboex.CodeGen.GenerationWorker
alias Blackboex.Apis.Conversations

defp maybe_enqueue_generation(api, description, user_id, org_id) do
  {:ok, conversation} = Conversations.get_or_create_conversation(api.id)
  Conversations.append_message(conversation, "user", description)
  %{api_id: api.id, description: description, user_id: user_id, org_id: org_id}
  |> GenerationWorker.new()
  |> Oban.insert()
end
```

**Comportamento necessário:**
```elixir
alias Blackboex.Agent.KickoffWorker
alias Blackboex.Apis

defp maybe_enqueue_generation(api, description, user_id, org_id) do
  if Apis.agent_pipeline_enabled?() do
    Apis.start_agent_generation(api, description, user_id)
  else
    # Fallback antigo
    %{api_id: api.id, description: description, user_id: user_id, org_id: org_id}
    |> Blackboex.CodeGen.GenerationWorker.new()
    |> Oban.insert()
  end
end
```

---

### TASK 7: Remover handler de polling `check_generation_status`

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas atuais:** 2009-2042

**Comportamento atual:** Timer que checa `api.generation_status` a cada 5 segundos via polling do DB.

**Comportamento necessário:** Quando agent pipeline está ativo, NÃO usar polling. O agent notifica via PubSub. Manter o polling como fallback se flag está off.

```elixir
def handle_info(:check_generation_status, socket) do
  if Apis.agent_pipeline_enabled?() do
    # Agent pipeline usa PubSub, não precisa de polling
    {:noreply, socket}
  else
    # Manter polling antigo como fallback
    # ... código existente ...
  end
end
```

---

### TASK 8: Handler `{:generation_complete}` — versão agent

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas atuais:** 2156-2210

**Comportamento atual:** Recebe `{:generation_complete, result}` do GenerationWorker, carrega API do DB, atualiza editor, appenda mensagem no chat JSONB.

**Comportamento necessário:** Este handler é do pipeline antigo. O novo agent emite `{:agent_completed}`. As duas mensagens coexistem durante a transição. Manter `{:generation_complete}` para o pipeline antigo e adicionar `{:agent_completed}` handler (TASK 4).

---

### TASK 9: Reescrever `do_accept_edit` — versão agent

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas atuais:** 2270-2312

**Comportamento atual:** Quando user aceita um edit proposto pelo chat, aplica o código no editor e chama `UnifiedPipeline.validate_and_test` via `Task.async`.

**Comportamento necessário com agent:**
O fluxo de accept/reject muda fundamentalmente. No modelo agent, o LLM já compilou, testou e validou antes de submeter. O `submit_code` tool só é chamado quando tudo passa. Portanto:

- Quando `{:agent_completed}` chega, o código JÁ ESTÁ validado
- Não precisa de etapa separada "aceitar → validar"
- O LiveView deve aplicar o código diretamente no editor

Se quisermos manter review antes de aplicar (diff modal):
1. Quando `{:agent_completed, %{code: code}}` chega, mostrar diff modal
2. User clica "Accept" → aplica código (já validado)
3. User clica "Reject" → descarta

Isso é MUITO mais simples que o fluxo atual. A função `do_accept_edit` pode ser simplificada para apenas `push_editor_value` + `Apis.update_api`.

---

### TASK 10: Reescrever `start_validation_pipeline` — versão agent

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas atuais:** 2451-2460

**Comportamento atual:** Chamado quando user salva código manualmente (não via chat). Chama `UnifiedPipeline.validate_on_save`.

**Comportamento necessário:** Manter como está (validação local sem LLM) OU criar um `run_type: "test_only"` que apenas compila e testa sem gerar código novo. A validação on-save não precisa passar pelo agent — é uma operação determinística.

**Recomendação:** Manter `validate_on_save` como está. Não precisa do agent para validação pura.

---

### TASK 11: Novo assign `agent_events` e componente de timeline

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex` + template

**O que precisa:**
1. Novo assign `agent_events: []` — lista de ações do agent em tempo real
2. Componente/partial que renderiza essa timeline no chat panel:
   ```
   🔄 Compiling code...
   ❌ Compilation failed (3 errors)
   🔄 Fixing compilation errors...
   ✅ Compiled successfully
   🔄 Running tests...
   ❌ 2 of 5 tests failed
   🔄 Analyzing test failures...
   ✅ All tests passing
   ✅ Code submitted
   ```
3. Cada entrada na timeline vem de `{:agent_action}`, `{:tool_result}`, `{:agent_message}` handlers
4. A timeline limpa quando um novo run começa

**Localização do template:** Verificar onde o chat panel é renderizado em edit.ex (procurar por `chat_panel` ou `chat_messages` no template/render function). O componente de timeline deve ser inserido ali.

---

### TASK 12: Criar admin resources Backpex para Conversation/Run/Event

**Diretório:** `apps/blackboex_web/lib/blackboex_web/admin/resources/`

**Arquivos a criar:**

1. `conversation_resource.ex` — Lista conversations por API, mostra stats (total_runs, total_cost_cents)
2. `run_resource.ex` — Lista runs com filtro por status/run_type, mostra iteration_count, duration_ms, cost_cents, final_code
3. `event_resource.ex` — Lista events com filtro por event_type/tool_name, mostra sequence, content, tool_success

**Referência:** Olhar os resources existentes em `apps/blackboex_web/lib/blackboex_web/admin/resources/` para seguir o padrão Backpex do projeto.

**Router:** Verificar `apps/blackboex_web/lib/blackboex_web/router.ex` na seção admin e adicionar rotas para os novos resources.

---

### TASK 13: Migrar imports/aliases em edit.ex

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`

**Imports a adicionar:**
```elixir
alias Blackboex.Conversations, as: AgentConversations  # novo contexto
alias Blackboex.Conversations.Run
```

**Imports a manter (para fallback do pipeline antigo durante transição):**
```elixir
alias Blackboex.Apis.Conversations  # antigo — manter até remover pipeline v1
alias Blackboex.CodeGen.UnifiedPipeline  # antigo — manter para validate_on_save
```

---

### TASK 14: Garantir que `{:generation_token}` handlers ainda funcionam durante transição

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/live/api_live/edit.ex`
**Linhas:** 2045-2076

Durante a transição (feature flag parcial), AMBOS os pipelines podem estar ativos. O handler `{:generation_token, token}` deve continuar existindo para o pipeline antigo. O novo handler `{:agent_streaming, %{delta: delta}}` é adicionado separadamente.

**Não deletar nenhum handler antigo.** Apenas adicionar os novos. A limpeza será feita quando o pipeline antigo for removido.

---

### TASK 15: Testes para os novos handlers do LiveView

**Diretório:** `apps/blackboex_web/test/blackboex_web/live/api_live/`

**Testes necessários:**

1. **Test agent chat flow:**
   - User envia mensagem → job é enfileirado (mock Oban)
   - `{:agent_run_started}` → assigns atualizados (chat_loading, current_run_id)
   - `{:agent_streaming}` → streaming_tokens acumula
   - `{:agent_completed}` → código aplicado, loading false, flash info

2. **Test agent failure:**
   - `{:agent_failed}` → loading false, flash error

3. **Test agent timeline:**
   - `{:agent_action}` → agent_events atualizado
   - `{:tool_result}` → agent_events atualizado

4. **Test feature flag fallback:**
   - Flag off → usa pipeline antigo (GenerationWorker)
   - Flag on → usa agent pipeline (KickoffWorker)

5. **Test generation via index.ex:**
   - Criar API com flag on → KickoffWorker enfileirado
   - Criar API com flag off → GenerationWorker enfileirado

---

### TASK 16: Verificar e corrigir chat_panel component

**Arquivo:** `apps/blackboex_web/lib/blackboex_web/components/chat_panel.ex`

**Issue encontrado (linha 190-196):** A função `test_summary` assume que `test_results` tem campos com atom keys (`.status`), mas os events do agent armazenam como string keys. Corrigir para suportar ambos:

```elixir
defp test_summary(test_results) when is_list(test_results) and test_results != [] do
  passed = Enum.count(test_results, fn
    %{"status" => "passed"} -> true
    %{status: "passed"} -> true
    _ -> false
  end)
```

---

### TASK 17: Adicionar has_one :conversation no schema Api

**Arquivo:** `apps/blackboex/lib/blackboex/apis/api.ex`

**Adicionar dentro do schema:**
```elixir
has_one :conversation, Blackboex.Conversations.Conversation
```

Isso permite `Repo.preload(api, :conversation)` e facilita queries.

---

### TASK 18: Wire recovery para APIs com generation_status stuck

**Cenário:** Uma API com `generation_status: "generating"` mas cujo Run já completou/falhou.

No mount do edit.ex, se o agent pipeline está ativo, checar:
```elixir
if api.generation_status in ["pending", "generating", "validating"] do
  # Verificar se há um run ativo para esta API
  conversation = AgentConversations.get_conversation_by_api(api.id)
  if conversation do
    active_run = AgentConversations.list_runs(conversation.id, limit: 1)
                 |> Enum.find(&(&1.status == "running"))
    if active_run do
      # Tem run ativo — subscribe e esperar
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{active_run.id}")
    else
      # Nenhum run ativo — o generation_status está stuck
      # O RecoveryWorker pode ter marcado o run como failed
      # Recarregar API do DB para pegar o status mais recente
      api = Apis.get_api(org.id, api.id)
    end
  end
end
```

---

### TASK 19: Documentar protocolo PubSub no moduledoc

**Arquivo:** `apps/blackboex/lib/blackboex/agent/callbacks.ex`

Adicionar no `@moduledoc` uma seção documentando TODAS as mensagens PubSub emitidas, seus topics, e o formato dos payloads. Isso serve como contrato entre backend e frontend.

---

### TASK 20: Validação final completa

Após todas as tasks acima:

```bash
# Compilação sem warnings
mix compile --warnings-as-errors

# Formatação
mix format --check-formatted

# Credo strict
mix credo --strict

# Testes completos
mix test

# Dialyzer
mix dialyzer
```

**Todos devem passar com zero erros.**

---

## Ordem de Execução Recomendada

```
TASK 17 (has_one) → simples, sem dependências
TASK 13 (imports) → preparação
TASK 3 (assign current_run_id + subscription) → fundação
TASK 4 (novos handlers) → core da integração
TASK 5 (chat history dos events) → display
TASK 1 (reescrever send_chat) → wiring principal
TASK 2 (reescrever do_chat_llm_call) → consequência de TASK 1
TASK 6 (index.ex generation) → entrada alternativa
TASK 7 (remover polling) → cleanup
TASK 8 (generation_complete coexistência) → transição
TASK 9 (do_accept_edit simplificado) → UX update
TASK 10 (validate_on_save) → decisão: manter como está
TASK 11 (timeline component) → UI nova
TASK 12 (admin resources) → observabilidade
TASK 14 (coexistência handlers) → segurança
TASK 15 (testes) → validação
TASK 16 (chat_panel fix) → bugfix
TASK 18 (recovery stuck) → robustez
TASK 19 (documentação) → manutenibilidade
TASK 20 (validação final) → gate de qualidade
```

## Regras do Projeto

- Elixir: `mix format` enforced, Credo strict, Dialyzer
- Toda função pública DEVE ter `@spec`
- LiveViews devem ser thin — delegar para domain contexts
- Tags de teste: `@tag :unit`, `@tag :integration`, `@tag :liveview`
- NUNCA fazer commit sem o usuário pedir
- Feature flag `agent_pipeline` controla qual pipeline está ativo
- O pipeline antigo DEVE continuar funcionando como fallback durante a transição
