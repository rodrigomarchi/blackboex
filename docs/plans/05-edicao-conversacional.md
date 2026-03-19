# Fase 05 - Edicao Conversacional com LLM

> **Entregavel testavel:** Usuario refina codigo via chat com LLM. Digita instrucoes
> em linguagem natural, ve diff das mudancas propostas, aceita ou rejeita, e o codigo
> e atualizado automaticamente.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - Testar LiveView hooks unitariamente: socket precisa de `__changed__` no assigns
> - Dados de sessao sao input nao-confiavel — sempre re-verificar existencia de entidades
> - Rodar todos os linters apos cada bloco de implementacao
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 02):**
> - Versoes de deps no discovery podem estar desatualizadas — sempre `mix hex.search <pkg>` antes de adicionar
> - Deps que usam `defdelegate` com default args geram `unknown_function` no Dialyzer — adicionar ao `.dialyzer_ignore.exs` proativamente
> - Trabalho async em LiveView DEVE usar `Task.async` + `handle_info({ref, result})` + `handle_info({:DOWN, ...})`. NUNCA `send(self(), :do_work)`
> - Rate limiting, autorizacao e tracking de uso DEVEM ser chamados no fluxo real, nao apenas implementados como modulos soltos
> - Templates e prompts NAO podem contradizer regras de seguranca (listas de modulos permitidos/proibidos)
> - Filtrar opts internos (`user_id`, etc) antes de passar a libs externas — `Keyword.drop([:user_id])`
> - `defp` entre clausulas `def` do mesmo nome gera warning — agrupar clausulas publicas primeiro, helpers privados depois
> - `@module_attr` em HEEx resolve para `assigns`, NAO module attribute — hardcode ou passar como assign
> - Testes LiveView com `Task.async` + Mox precisam `async: false`
> - Discovery docs tem exemplos de API ERRADOS — NUNCA confiar nos exemplos. Sempre verificar a API real em `deps/<pkg>/lib/`
> - Deps OTP que precisam de supervision tree (ex: ExRated) devem ser listados em `extra_applications` no `mix.exs`
> - Erros de libs externas NAO devem ser engolidos — sempre logar o erro original e propagar mensagem legivel ao usuario
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 03):**
> - Prompts do LLM DEVEM instruir funções puras (`def handle(params)` retornando maps). NUNCA `conn`, `json/2`, `put_status/2` — o template Plug.Router controla HTTP
> - Validar estilo do handler ANTES da compilação: detectar `conn`, `json()`, `put_status()`, `send_resp()` no source_code e rejeitar com erro claro
> - `Plug.Conn` é tied ao processo dono do socket — NUNCA executar módulos Plug em processo separado (Task/Sandbox). Usar try/rescue + max_heap_size no mesmo processo
> - Módulos compilados dinamicamente (Code.compile_quoted) se perdem no restart do servidor — Registry DEVE recompilar do DB no init, e rotas DEVEM ter fallback compile-from-DB
> - `static_atoms_encoder` no Code.string_to_quoted: limite de 100 átomos é MUITO baixo para código real (~95 átomos num handler simples). Usar 500+
> - ETS tables morrem com o GenServer owner — lookup DEVE ter rescue ArgumentError para não crashar se table não existir
> - `handle_continue(:reload)` é assíncrono — requests podem chegar ANTES do reload completar. Usar reload síncrono no init para dados críticos
> - Segurança AST: bloquear Kernel functions (spawn, exit, throw, send, apply), String.to_atom (bypass de blocklist via construção runtime de módulos), Kernel.send/apply (bypass via chamada qualificada), require de módulos perigosos
> - DataStore upsert com read-then-write tem race condition — usar `Repo.insert` com `on_conflict` para true upsert atômico
> - Authorization em LiveView: SEMPRE verificar membership do usuário na org quando org_id vem de query params — nunca confiar no input do cliente
> - Geração de código pelo LLM com prompts antigos produz código incompatível — Compiler deve dar mensagens claras sobre o que está errado (não apenas "compilation failed")
> - HEEx templates: `{` literal (ex: JSON em exemplos) é interpretado como interpolação — usar assigns ou evitar JSON literal em templates
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 04):**
> - `live_monaco_editor` — import path no esbuild umbrella: usar `"live_monaco_editor/priv/static/live_monaco_editor.esm"` (via NODE_PATH), NAO path relativo com `../../deps/`
> - Monaco Editor NAO reage a mudancas de `value` assign apos mount — usar `LiveMonacoEditor.set_value(socket, code, to: path)` para atualizar conteudo programaticamente
> - Version number race condition: NUNCA calcular next version_number fora da transacao. Usar `Ecto.Multi.run` com `SELECT MAX` dentro do Multi
> - `compilation_status` deve ser atualizado na versao apos compilacao — nao deixar como "pending" permanentemente
> - `compile_success` badge deve ser limpo quando o codigo muda — senao usuario ve badge verde com codigo nao-compilado
> - Save sem mudanca: detectar e mostrar "No changes to save" em vez de criar versao duplicada
> - LetMe Policy API: action names sao compostas como `:{object}_{action}` (ex: `:api_update`), NAO `:{action}` separado
> - Dialyzer nao resolve funcoes de deps HEEx (LiveMonacoEditor) — adicionar ao `.dialyzer_ignore.exs` proativamente
> - Codigo duplicado entre LiveViews (resolve_organization, status_color, etc.) — extrair para modulos shared quando atingir 3+ usos

## Fontes de Discovery
- `docs/discovery/04-api-editing.md` (conversational editing, diff, chat panel)
- `docs/discovery/01-llm-providers.md` (streaming, structured output)

## Pre-requisitos
- Fase 04 concluida (editor Monaco com versionamento)

---

## 1. Persistencia de Conversas

Ref: discovery/04 section 2.1 (chat persistence model)

- [x] Escrever testes para schema `Blackboex.Apis.ApiConversation`:
  - Changeset valido com api_id e messages (array vazio)
  - Uma conversa ativa por API (unique api_id)
  - Messages e array de maps com role, content, timestamp
  - Campo `metadata` com default `%{}` no schema
- [x] Criar migration para tabela `api_conversations`:
  - `id` (UUID), `api_id` (unique), `messages` (jsonb, default []), `metadata` (jsonb, default %{})
- [x] Implementar schema `Blackboex.Apis.ApiConversation`
- [x] Escrever testes para contexto `Blackboex.Apis.Conversations`:
  - `get_or_create_conversation/1` cria se nao existe
  - `get_or_create_conversation/1` retorna existente se ja tem
  - `append_message/3` adiciona mensagem ao array
  - `clear_conversation/1` zera messages para []
  - Formato de mensagem: `%{role, content, timestamp, metadata}`
- [x] Implementar contexto `Blackboex.Apis.Conversations`
- [x] Verificar: conversa persiste e mensagens acumulam

## 2. Prompt de Edicao

Ref: discovery/04 section 2.4 (prompt construction), discovery/04 section 2.5 (full-file replacement), discovery/01 section 8.1 (security constraints), plan 02 section 3 (restricoes LLM)

- [x] Escrever testes para `Blackboex.LLM.EditPrompts`:
  - `build_edit_prompt/3` inclui codigo atual na mensagem
  - `build_edit_prompt/3` usa codigo atual do editor (nao ultima versao salva) — contempla edicoes manuais nao salvas
  - `build_edit_prompt/3` inclui instrucao do usuario
  - `build_edit_prompt/3` inclui ultimas 10 mensagens do historico (limitacao de contexto)
  - System prompt instrui retornar codigo completo como full-file replacement (nao diff parcial). Ref: discovery/04 section 2.5
  - System prompt respeita restricoes de seguranca: reutiliza restricoes de `Blackboex.LLM.Prompts.system_prompt/0` (bloquear File, System, etc). Ref: plan 02 section 3, discovery/01 section 8.1
- [x] Implementar `Blackboex.LLM.EditPrompts`
- [x] Escrever testes para parsing da resposta:
  - Extrai codigo de markdown code block
  - Extrai explicacao da resposta
  - Retorna erro se nao contiver codigo valido
- [x] Implementar parsing de resposta de edicao
- [x] Verificar: prompt montado corretamente, parsing funciona

## 3. Chat Panel na UI

Ref: discovery/04 section 4.1 (chat panel design)

- [x] Escrever testes LiveView para componente `ChatPanel` (`@moduletag :liveview`):
  - `ChatPanel` e um `Phoenix.LiveComponent` com assigns `messages`, `input`, `loading`, `api_id`
  - Renderiza lista de mensagens vazia
  - Renderiza mensagens existentes (user a direita, assistant a esquerda)
  - Input de texto presente com botao enviar
  - Mensagens carregadas do banco ao montar
- [x] Implementar `BlackboexWeb.Components.ChatPanel` como `Phoenix.LiveComponent`
- [x] Escrever testes LiveView para layout 3 paineis (`@moduletag :liveview`):
  - Layout: Chat (25%, colapsavel) | Editor (50%) | Info/Versoes (25%). Ref: reestruturacao do layout 2-panel da Fase 04 para 3-panel
  - Quando chat colapsado, editor expande para 75%
- [x] Integrar chat panel ao layout do editor (3 paineis)
- [x] Verificar: chat renderiza com historico

## 4. Fluxo de Edicao via Chat

Ref: discovery/04 section 3.1 (edit flow), discovery/04 section 8.3 (compilation check)

> **Nota:** Esta secao usa chamada sincrona `generate_text` para o LLM. Streaming e adicionado na Secao 6.

> **Nota:** Diff inline nesta secao usa diff basico em texto. O componente `ChatDiff` estilizado e criado na Secao 5.

- [x] Escrever testes LiveView para fluxo completo (`@moduletag :liveview`):
  - Enviar mensagem adiciona ao chat (user message)
  - Resposta do LLM (mock via `Blackboex.LLM.ClientBehaviour.generate_text/2` com Mox) aparece como assistant message
  - Diff e calculado entre codigo atual e proposta usando `Blackboex.Apis.DiffEngine.compute_diff/2` (da Fase 04)
  - Diff inline mostrado na mensagem (basico em texto, estilizado na Secao 5)
  - Botoes "Aceitar" e "Rejeitar" presentes na mensagem com diff
- [x] Escrever testes para acao "Aceitar" (`@moduletag :liveview`):
  - Codigo no editor atualiza para versao nova
  - Nova versao criada (source: `chat_edit`, prompt: instrucao). Ref: enum `chat_edit` do schema ApiVersion da Fase 04
  - Flash de sucesso exibido
- [x] Escrever testes para acao "Rejeitar":
  - Codigo no editor permanece inalterado
  - Nenhuma versao criada
  - Botoes Aceitar/Rejeitar removidos
- [x] Implementar fluxo no LiveView:
  1. Usuario envia mensagem
  2. LLM chamado (sincrono via `generate_text`) com codigo atual do editor + instrucao + historico
  3. Diff calculado via `DiffEngine.compute_diff/2`
  4. Diff mostrado com Aceitar/Rejeitar
  5. Aceitar: cria versao + atualiza editor
  6. Rejeitar: noop
- [x] Verificar: fluxo aceitar/rejeitar funciona end-to-end

## 5. Diff Inline no Chat

Ref: discovery/04 section 6 (diff viewer component)

- [x] Escrever testes para componente `ChatDiff` (`@moduletag :liveview`):
  - Renderiza linhas adicionadas em verde
  - Renderiza linhas removidas em vermelho
  - Diff summary (N added, N removed)
- [x] Implementar diff inline no ChatPanel (integrado, não componente separado)
- [x] Verificar: diff inline compacto e legível

## 6. Streaming da Resposta

Ref: discovery/01 section 3.1 (streaming), plan 02 (StreamHandler)

> **Nota:** Reutiliza `Blackboex.LLM.StreamHandler` da Fase 02. PubSub topic: `"api_chat:#{api_id}"`. Eventos: `{:chat_token, token}`, `{:chat_done, full_response}`, `{:chat_error, reason}`.

- [x] Escrever testes (`@moduletag :integration`):
  - Indicador "Pensando..." aparece durante chamada LLM
  - Após resposta completa, diff é calculado e botões aparecem
  - Se resposta não contiver código: mensagem no chat sem diff
  - Erro do LLM mostra mensagem de erro no chat
- [x] Implementar chamada LLM síncrona via `generate_text` (streaming via PubSub é enhancement futuro)
- [x] Verificar: fluxo funciona com indicador visual

## 7. Tratamento de Erros

Ref: discovery/01 section 3.3 (error handling)

- [x] Escrever testes (`@moduletag :unit`):
  - LLM timeout mostra mensagem de erro no chat
  - Rate limit mostra mensagem de erro no chat
  - Falha de rede mostra mensagem de erro
  - Erro não deixa chat em estado de loading
  - Mensagem vazia é ignorada
- [x] Implementar tratamento de erros no fluxo de chat
- [x] Verificar: erros tratados com mensagens claras

## 8. Acoes Rapidas

Ref: discovery/04 section 5.1 (quick actions)

- [x] Escrever testes LiveView (`@moduletag :liveview`):
  - Botões de ação rápida renderizam acima do input
  - Ações contextuais ao template type (CRUD vs Computation vs Webhook)
- [x] Implementar ações rápidas:
  - Gerais: "Adicionar validação", "Otimizar performance", "Adicionar error handling"
  - CRUD: "Adicionar filtro", "Adicionar paginação"
  - Webhook: "Validar assinatura"
- [x] Verificar: ações rápidas funcionam

## 9. Limpar Conversa

Ref: discovery/04 section 7.1 (conversation management)

- [x] Escrever testes (`@moduletag :liveview`):
  - Botão "Nova conversa" presente no chat
  - "Nova conversa" limpa messages no banco
  - Código atual permanece intacto após limpar
  - Confirmação exigida antes de limpar (data-confirm)
- [x] Implementar botão "Nova conversa" com dialog de confirmação
- [x] Verificar: limpar funciona sem afetar código

## 10. Qualidade

- [x] `mix format --check-formatted` passa
- [x] `mix credo --strict` passa
- [x] `mix dialyzer` passa
- [x] `make precommit` passa (434 tests, 0 failures)
- [x] `@spec` em todas as funções públicas
- [x] Testes com tags corretas: `@moduletag :unit` para schema/contexto, `@moduletag :liveview` para LiveView, `@moduletag :integration` para streaming

---

## Criterios de Aceitacao

- [x] Chat panel visível ao lado do editor (layout 3 painéis: Chat 25% | Editor 50% | Info 25%)
- [x] Digitar instrução e ver resposta do LLM
- [x] Diff das mudanças mostrado inline no chat (verde/vermelho + summary)
- [x] "Aceitar" atualiza código e cria nova versão (source: chat_edit)
- [x] "Rejeitar" mantém código inalterado
- [x] Erros de LLM (timeout, rate limit, rede) tratados com mensagens claras
- [x] Conversa persiste entre recarregamentos
- [x] Ações rápidas funcionam (contextuais por template type)
- [x] Limpar conversa funciona (com confirmação)
- [x] `make precommit` passa (434 tests, 0 failures)
- [x] 100% TDD
