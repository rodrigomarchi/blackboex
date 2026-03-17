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

## Fontes de Discovery
- `docs/discovery/04-api-editing.md` (conversational editing, diff, chat panel)
- `docs/discovery/01-llm-providers.md` (streaming, structured output)

## Pre-requisitos
- Fase 04 concluida (editor Monaco com versionamento)

---

## 1. Persistencia de Conversas

Ref: discovery/04 section 2.1 (chat persistence model)

- [ ] Escrever testes para schema `Blackboex.Apis.ApiConversation`:
  - Changeset valido com api_id e messages (array vazio)
  - Uma conversa ativa por API (unique api_id)
  - Messages e array de maps com role, content, timestamp
  - Campo `metadata` com default `%{}` no schema
- [ ] Criar migration para tabela `api_conversations`:
  - `id` (UUID), `api_id` (unique), `messages` (jsonb, default []), `metadata` (jsonb, default %{})
- [ ] Implementar schema `Blackboex.Apis.ApiConversation`
- [ ] Escrever testes para contexto `Blackboex.Apis.Conversations`:
  - `get_or_create_conversation/1` cria se nao existe
  - `get_or_create_conversation/1` retorna existente se ja tem
  - `append_message/3` adiciona mensagem ao array
  - `clear_conversation/1` zera messages para []
  - Formato de mensagem: `%{role, content, timestamp, metadata}`
- [ ] Implementar contexto `Blackboex.Apis.Conversations`
- [ ] Verificar: conversa persiste e mensagens acumulam

## 2. Prompt de Edicao

Ref: discovery/04 section 2.4 (prompt construction), discovery/04 section 2.5 (full-file replacement), discovery/01 section 8.1 (security constraints), plan 02 section 3 (restricoes LLM)

- [ ] Escrever testes para `Blackboex.LLM.EditPrompts`:
  - `build_edit_prompt/3` inclui codigo atual na mensagem
  - `build_edit_prompt/3` usa codigo atual do editor (nao ultima versao salva) — contempla edicoes manuais nao salvas
  - `build_edit_prompt/3` inclui instrucao do usuario
  - `build_edit_prompt/3` inclui ultimas 10 mensagens do historico (limitacao de contexto)
  - System prompt instrui retornar codigo completo como full-file replacement (nao diff parcial). Ref: discovery/04 section 2.5
  - System prompt respeita restricoes de seguranca: reutiliza restricoes de `Blackboex.LLM.Prompts.system_prompt/0` (bloquear File, System, etc). Ref: plan 02 section 3, discovery/01 section 8.1
- [ ] Implementar `Blackboex.LLM.EditPrompts`
- [ ] Escrever testes para parsing da resposta:
  - Extrai codigo de markdown code block
  - Extrai explicacao da resposta
  - Retorna erro se nao contiver codigo valido
- [ ] Implementar parsing de resposta de edicao
- [ ] Verificar: prompt montado corretamente, parsing funciona

## 3. Chat Panel na UI

Ref: discovery/04 section 4.1 (chat panel design)

- [ ] Escrever testes LiveView para componente `ChatPanel` (`@moduletag :liveview`):
  - `ChatPanel` e um `Phoenix.LiveComponent` com assigns `messages`, `input`, `loading`, `api_id`
  - Renderiza lista de mensagens vazia
  - Renderiza mensagens existentes (user a direita, assistant a esquerda)
  - Input de texto presente com botao enviar
  - Mensagens carregadas do banco ao montar
- [ ] Implementar `BlackboexWeb.Components.ChatPanel` como `Phoenix.LiveComponent`
- [ ] Escrever testes LiveView para layout 3 paineis (`@moduletag :liveview`):
  - Layout: Chat (25%, colapsavel) | Editor (50%) | Info/Versoes (25%). Ref: reestruturacao do layout 2-panel da Fase 04 para 3-panel
  - Quando chat colapsado, editor expande para 75%
- [ ] Integrar chat panel ao layout do editor (3 paineis)
- [ ] Verificar: chat renderiza com historico

## 4. Fluxo de Edicao via Chat

Ref: discovery/04 section 3.1 (edit flow), discovery/04 section 8.3 (compilation check)

> **Nota:** Esta secao usa chamada sincrona `generate_text` para o LLM. Streaming e adicionado na Secao 6.

> **Nota:** Diff inline nesta secao usa diff basico em texto. O componente `ChatDiff` estilizado e criado na Secao 5.

- [ ] Escrever testes LiveView para fluxo completo (`@moduletag :liveview`):
  - Enviar mensagem adiciona ao chat (user message)
  - Resposta do LLM (mock via `Blackboex.LLM.ClientBehaviour.stream_text/2` com Mox) aparece como assistant message
  - Diff e calculado entre codigo atual e proposta usando `Blackboex.Apis.DiffEngine.compute_diff/2` (da Fase 04)
  - Diff inline mostrado na mensagem (basico em texto, estilizado na Secao 5)
  - Botoes "Aceitar" e "Rejeitar" presentes na mensagem com diff
- [ ] Escrever testes para acao "Aceitar" (`@moduletag :liveview`):
  - "Aceitar" executa `compile_check` no codigo proposto antes de criar versao. Ref: discovery/04 section 8.3
  - Se `compile_check` falha, mostra erros de compilacao no chat e NAO cria versao
  - Se `compile_check` passa, codigo no editor atualiza para versao nova
  - Nova versao criada (source: `chat_edit`, prompt: instrucao). Ref: enum `chat_edit` do schema ApiVersion da Fase 04
  - Mensagem marcada como accepted: true
- [ ] Escrever testes para acao "Rejeitar":
  - Codigo no editor permanece inalterado
  - Mensagem marcada como accepted: false
  - Nenhuma versao criada
- [ ] Implementar fluxo no LiveView:
  1. Usuario envia mensagem
  2. LLM chamado (sincrono via `generate_text`) com codigo atual do editor + instrucao + historico
  3. Diff calculado via `DiffEngine.compute_diff/2`
  4. Diff mostrado com Aceitar/Rejeitar
  5. Aceitar: compile_check -> se ok, atualiza editor + cria versao
  6. Rejeitar: noop
- [ ] Verificar: fluxo aceitar/rejeitar funciona end-to-end

## 5. Diff Inline no Chat

Ref: discovery/04 section 6 (diff viewer component)

- [ ] Escrever testes para componente `ChatDiff` (`@moduletag :liveview`):
  - Renderiza linhas adicionadas em verde
  - Renderiza linhas removidas em vermelho
  - Limita a ~20 linhas com "ver mais" se necessario
  - Botao "Ver diff completo" presente
- [ ] Implementar `BlackboexWeb.Components.ChatDiff`
- [ ] "Ver diff completo" abre Monaco diff editor via componente `BlackboexWeb.Components.DiffViewer` (da Fase 04, Section 6)
- [ ] Verificar: diff inline compacto e legivel

## 6. Streaming da Resposta

Ref: discovery/01 section 3.1 (streaming), plan 02 (StreamHandler)

> **Nota:** Reutiliza `Blackboex.LLM.StreamHandler` da Fase 02. PubSub topic: `"api_chat:#{api_id}"`. Eventos: `{:chat_token, token}`, `{:chat_done, full_response}`, `{:chat_error, reason}`.

- [ ] Escrever testes (`@moduletag :integration`):
  - Indicador "Pensando..." aparece durante streaming
  - Chunks da resposta aparecem progressivamente na mensagem
  - Apos stream completo, diff e calculado e botoes aparecem
  - Se resposta nao contiver codigo: mensagem de erro no chat
  - Streaming usa `Blackboex.LLM.ClientBehaviour.stream_text/2` (via Mox mock em testes)
- [ ] Implementar streaming no LiveView via PubSub:
  - Subscribe em `"api_chat:#{api_id}"`
  - Handle `{:chat_token, token}` para atualizar mensagem progressivamente
  - Handle `{:chat_done, full_response}` para calcular diff e mostrar botoes
  - Handle `{:chat_error, reason}` para mostrar erro
- [ ] Verificar: streaming funciona com indicador visual

## 7. Tratamento de Erros

Ref: discovery/01 section 3.3 (error handling)

- [ ] Escrever testes (`@moduletag :unit`):
  - LLM timeout mostra mensagem de erro no chat ("A requisicao demorou demais, tente novamente")
  - Rate limit mostra mensagem amigavel ("Muitas requisicoes, aguarde um momento")
  - Falha de rede permite retry (botao "Tentar novamente" na mensagem de erro)
- [ ] Implementar tratamento de erros no fluxo de chat
- [ ] Verificar: erros tratados com mensagens claras e opcao de retry

## 8. Acoes Rapidas

Ref: discovery/04 section 5.1 (quick actions)

- [ ] Escrever testes LiveView (`@moduletag :liveview`):
  - Botoes de acao rapida renderizam acima do input
  - Clicar acao rapida preenche input com texto pre-definido
  - Acoes contextuais ao template type (CRUD vs Computation vs Webhook)
- [ ] Implementar acoes rapidas:
  - Gerais: "Adicionar validacao", "Otimizar performance", "Adicionar error handling"
  - CRUD: "Adicionar filtro", "Adicionar paginacao"
  - Computation: "Adicionar cache"
  - Webhook: "Validar assinatura"
- [ ] Verificar: acoes rapidas funcionam

## 9. Limpar Conversa

Ref: discovery/04 section 7.1 (conversation management)

- [ ] Escrever testes (`@moduletag :unit` para contexto, `@moduletag :liveview` para UI):
  - "Nova conversa" limpa messages no banco
  - Codigo atual permanece intacto apos limpar
  - Confirmacao exigida antes de limpar
- [ ] Implementar botao "Nova conversa" com dialog de confirmacao
- [ ] Verificar: limpar funciona sem afetar codigo

## 10. Qualidade

- [ ] `mix format --check-formatted` passa
- [ ] `mix credo --strict` passa
- [ ] `mix dialyzer` passa
- [ ] `make precommit` passa
- [ ] `@spec` em todas as funcoes publicas
- [ ] Testes com tags corretas: `@moduletag :unit` para schema/contexto, `@moduletag :liveview` para LiveView, `@moduletag :integration` para PubSub/streaming

---

## Criterios de Aceitacao

- [ ] Chat panel visivel ao lado do editor (layout 3 paineis: Chat 25% | Editor 50% | Info 25%)
- [ ] Digitar instrucao e ver resposta do LLM em streaming
- [ ] Diff das mudancas mostrado inline no chat
- [ ] "Aceitar" executa compile_check e, se ok, atualiza codigo e cria nova versao
- [ ] "Rejeitar" mantem codigo inalterado
- [ ] Erros de LLM (timeout, rate limit, rede) tratados com mensagens claras
- [ ] Conversa persiste entre recarregamentos
- [ ] Acoes rapidas funcionam
- [ ] Limpar conversa funciona
- [ ] `make precommit` passa
- [ ] 100% TDD
