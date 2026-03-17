# Fase 04 - Editor de Codigo & Versionamento

> **Entregavel testavel:** Usuario edita codigo no browser com Monaco Editor,
> salva versoes, ve historico, faz rollback, e recompila — tudo sem sair da pagina.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - `live_monaco_editor` — verificar se precisa de `import_deps` no `.formatter.exs`
> - Testar LiveView hooks unitariamente: socket precisa de `__changed__` no assigns
> - Mudancas em rotas/layout quebram testes existentes — rodar suite completa a cada mudanca
> - Rodar todos os linters apos cada bloco de implementacao

## Fontes de Discovery
- `docs/discovery/04-api-editing.md` (Monaco, versionamento, hot reload, diffs)

## Pre-requisitos
- Fase 03 concluida (APIs compilam e executam)

---

## 1. Monaco Editor Integration

Ref: discovery/04 secoes 1.1–1.4 (Monaco setup, hooks, lifecycle, debounce)

- [ ] Adicionar `live_monaco_editor ~> 0.2` ao `mix.exs` do app web
- [ ] Configurar assets:
  - Importar `CodeEditorHook` em `app.js`
  - Adicionar hook ao objeto `hooks` do `LiveSocket`
  - Verificar configuracao do esbuild para bundle correto
- [ ] Escrever teste LiveView para componente `CodeEditor`:
  - Renderiza elemento com atributos corretos (`phx-hook`, `data-language`, `data-code`). Nota: ExUnit nao testa renderizacao JS — verificar que o hook element e emitido com atributos corretos
  - Emite evento `code-changed` ao editar
  - Modo read-only funciona
- [ ] Implementar componente `BlackboexWeb.Components.CodeEditor`:
  - Props: `code`, `language`, `read_only`, `on_change`
  - Monaco com tema escuro + syntax highlighting Elixir
  - Estrategia de debounce: save-on-blur + Ctrl+S (NAO enviar eventos por keystroke). Ref: discovery/04 secao 1.4
  - Hook lifecycle: chamar `editor.dispose()` no callback `destroyed()`. Ref: discovery/04 secao 1.3
- [ ] Verificar: Monaco renderiza no browser

## 2. Tela de Edicao

Ref: discovery/04 secao 2.1 (layout, abas, permissoes)

- [ ] Escrever testes LiveView para `BlackboexWeb.ApiLive.Edit`:
  - Renderiza com codigo da API carregado no editor
  - Mostra nome, status, slug no header
  - Mostra abas: Info, Versoes, Teste Rapido
  - Usuario nao logado redirecionado
  - Usuario sem permissao ve erro 403 — verificar autorizacao `:update` em Api via `Blackboex.Policy`
- [ ] Implementar LiveView `BlackboexWeb.ApiLive.Edit`:
  - Header: nome da API, status badge, botoes de acao
  - Painel esquerdo (60%): Monaco Editor
  - Painel direito (40%): abas (Info, Versoes, Teste Rapido)
  - Footer: botoes "Salvar", "Compilar"
- [ ] Aba "Info": nome, slug, descricao, template type, URL (se compilada)
- [ ] Aba "Teste Rapido": URL + selector method + body textarea + botao enviar + resposta
- [ ] Verificar: navegacao da lista de APIs para o editor funciona

## 3. Salvar & Compilar

Ref: discovery/04 secoes 2.2–2.3 (save flow, compilacao via Compiler)

- [ ] Escrever testes LiveView:
  - Evento "save" atualiza source_code no banco
  - Evento "compile" chama `Blackboex.CodeGen.Compiler.compile/2` da Fase 03 (NAO o Pipeline de geracao LLM) e atualiza status
  - Compilacao bem-sucedida mostra badge verde + URL
  - Compilacao falha mostra erros formatados com linha
  - Atalho Ctrl+S dispara save (via JS hook)
- [ ] Implementar acoes no LiveView:
  - "Salvar": atualiza `source_code`, toast de confirmacao
  - "Compilar": salva + `Blackboex.CodeGen.Compiler.compile/2` (inclui AST validation + build + compile + register)
  - Erros inline com referencia a numero de linha
- [ ] Verificar: editar -> salvar -> compilar funciona sem reload

## 4. Sistema de Versoes

Ref: discovery/04 secoes 3.1–3.2 (schema, auto-increment, source enum, llm_response)

- [ ] Escrever testes para schema `Blackboex.Apis.ApiVersion`:
  - Changeset valido com api_id, version_number, code, source
  - version_number auto-incrementa por API (1-based: primeira versao e 1)
  - source valido: `:generation`, `:manual_edit`, `:chat_edit`, `:rollback` (atoms, nao strings). Nota: discovery usa `:llm_generated, :user_edited, :llm_refined` — divergencia intencional para nomenclatura mais clara
- [ ] Criar migration para tabela `api_versions`:
  - `id` (UUID), `api_id`, `version_number`, `code`, `source`, `prompt` (nullable),
    `llm_response` (text, nullable — para debug de respostas LLM). Ref: discovery/04 secao 3.2,
    `compilation_status`, `compilation_errors` (nullable), `diff_summary` (nullable),
    `created_by_id`
  - `timestamps()`
  - unique index `[:api_id, :version_number]`
- [ ] Implementar schema `Blackboex.Apis.ApiVersion`
- [ ] Escrever testes para contexto:
  - `create_version/3` cria versao com numero incrementado (primeira = 1)
  - `list_versions/1` retorna versoes desc
  - `get_version/2` retorna versao especifica
  - `get_latest_version/1` retorna mais recente
  - Ao salvar edicao manual, versao e criada com source `:manual_edit`
  - Ao gerar codigo, versao e criada com source `:generation`
- [ ] Implementar funcoes de versionamento no contexto `Blackboex.Apis`
- [ ] Clarificar relacao `apis.source_code` vs `api_versions.code`: `apis.source_code` e cache da versao atual, atualizado na mesma transacao que a criacao da versao
- [ ] Verificar: cada save cria versao com numero incrementado

> **Nota:** `ApiConversation` intencionalmente adiado para Fase 05.

## 5. Diff entre Versoes

Ref: discovery/04 secao 4.1 (myers_difference, diff line-based)

- [ ] Escrever testes para `Blackboex.Apis.DiffEngine`:
  - `compute_diff/2` retorna diff para codigos diferentes
  - `compute_diff/2` retorna vazio para codigos iguais
  - `format_diff_summary/1` gera resumo legivel ("3 adicionadas, 1 removida")
- [ ] Implementar `DiffEngine`: dividir codigo em linhas com `String.split(code, "\n")` e aplicar `List.myers_difference/2`. Ref: discovery/04 secao 4.1
- [ ] Salvar `diff_summary` ao criar versao (comparando com anterior)
- [ ] Escrever teste LiveView: botao "Ver diff" abre diff viewer
- [ ] Implementar componente `DiffViewer` com Monaco diff editor (JS hook)
- [ ] Verificar: diffs calculados e exibidos corretamente

## 6. Historico de Versoes na UI

Ref: discovery/04 secao 5.1 (listagem, navegacao, diff_summary)

- [ ] Escrever testes LiveView para aba "Versoes":
  - Lista versoes em ordem decrescente
  - Cada item mostra: numero, source, data, status compilacao, diff_summary
  - Clicar em versao mostra codigo (read-only) no editor
  - Versao atual destacada
- [ ] Implementar aba "Versoes" no painel direito
- [ ] Verificar: historico navega entre versoes

## 7. Rollback

Ref: discovery/04 secao 6.1 (rollback como nova versao, recompilacao)

- [ ] Escrever testes:
  - `rollback_to_version/2` cria NOVA versao com source `:rollback`
  - Nova versao tem codigo da versao alvo
  - `source_code` da API e atualizado
  - Recompilacao automatica apos rollback — via `Compiler.compile/2` (inclui ASTValidator)
  - Historico preservado (rollback nao apaga versoes)
  - Apos rollback, modulo esta carregado E status da API e "compiled"
- [ ] Implementar `rollback_to_version/2` no contexto
- [ ] Escrever teste LiveView:
  - Botao "Restaurar" aparece em versoes antigas
  - Confirmacao antes de restaurar
  - Apos restaurar, editor mostra codigo antigo e status atualiza
- [ ] Implementar rollback na UI com dialog de confirmacao
- [ ] Verificar: rollback funciona end-to-end

## 8. Hot Reload

Ref: discovery/04 secao 7.1 (BEAM code loading, soft_purge, grace period)

- [ ] Escrever testes de integracao:
  - Compilar API v1 -> request retorna resultado v1
  - Compilar API v2 (sem parar) -> request retorna resultado v2
  - BEAM segura duas versoes simultaneamente
  - Soft purge remove versao antiga
- [ ] Implementar hot reload no `Compiler`:
  - Compilar novo modulo (BEAM segura current + old)
  - Hot reload DEVE passar pelo ASTValidator (reusar `Compiler.compile/2` que ja inclui validacao)
  - Grace period de 5s: apos carregar novo modulo, spawn Task que dorme 5s e chama `:code.soft_purge/1`. Se retornar false, retry ate 3x. Fallback final: `:code.purge/1`. Ref: discovery/04 secao 7.1
- [ ] Verificar: recompilar API ativa nao causa downtime

## 9. Qualidade

- [ ] `mix format --check-formatted` passa
- [ ] `mix credo --strict` passa
- [ ] `mix dialyzer` passa
- [ ] `make precommit` passa
- [ ] `@spec` em todas as funcoes publicas
- [ ] Testes: schema, contexto, LiveView, integracao hot reload

---

## Criterios de Aceitacao

- [ ] Monaco Editor renderiza com syntax highlighting Elixir
- [ ] Editar e salvar funciona (toast de confirmacao)
- [ ] Compilar mostra sucesso ou erros formatados com linha
- [ ] Cada save cria nova versao no historico (1-based numbering)
- [ ] Historico mostra versoes com metadata e diff_summary
- [ ] Clicar em versao antiga mostra codigo (read-only)
- [ ] Diff visual mostra mudancas entre versoes
- [ ] Rollback cria nova versao, recompila, e modulo fica carregado com status "compiled"
- [ ] Hot reload funciona sem downtime
- [ ] `make precommit` passa
- [ ] 100% TDD
