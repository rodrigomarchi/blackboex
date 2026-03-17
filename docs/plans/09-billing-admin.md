# Fase 09 - Billing & Painel Admin

> **Entregavel testavel:** Plataforma monetizavel com Stripe integration,
> planos free/pro/enterprise, painel admin para operadores, audit logging completo,
> e feature flags para rollout gradual.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - `backpex`, `ex_audit`, `fun_with_flags`, `oban`, `stripity_stripe` — TODAS usam macros/DSL. Adicionar cada uma a `import_deps` no `.formatter.exs` do app correspondente
> - Stripe webhooks usam IDs externos — nunca `Repo.get!` com dados de webhook, sempre `Repo.get` + pattern match
> - Rodar todos os linters apos cada bloco de implementacao
> - Atualizar `.dialyzer_ignore.exs` para falsos positivos se necessario

## Fontes de Discovery
- `docs/discovery/02-backoffice-config.md` (Backpex, billing, audit, feature flags)

## Pre-requisitos
- Fases 01-07 concluidas (plataforma funcional)

## Dependencias deste plano

```elixir
# apps/blackboex/mix.exs
{:stripity_stripe, "~> 3.2"},
{:ex_audit, "~> 0.10"},
{:fun_with_flags, "~> 1.0"},
{:oban, "~> 2.18"}

# apps/blackboex_web/mix.exs
{:backpex, "~> 0.17"}
```

---

## 1. Stripe Integration

Ref: discovery/02 secao Billing/Stripe

- [ ] Adicionar `{:stripity_stripe, "~> 3.2"}` ao `mix.exs` de `blackboex`
- [ ] Adicionar `{:oban, "~> 2.18"}` ao `mix.exs` de `blackboex` (necessario para usage aggregation workers)
- [ ] Configurar Oban no `application.ex` e `runtime.exs` (fila `:billing` com intervalo de polling)
- [ ] Configurar Stripe via env vars: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`
- [ ] Escrever testes para schema `Blackboex.Billing.Subscription`:
  - Changeset valido com org_id, stripe_customer_id, plan, status
  - Plans validos: "free", "pro", "enterprise"
  - Status validos: "active", "past_due", "canceled", "trialing"
- [ ] Criar migration para tabela `subscriptions`:
  - `id` (UUID), `organization_id` (unique), `stripe_customer_id`,
    `stripe_subscription_id`, `plan`, `status`, `current_period_start`,
    `current_period_end`, `cancel_at_period_end`
- [ ] Implementar schema `Blackboex.Billing.Subscription`
- [ ] Verificar: `mix test` passa com testes do schema

## 2. Checkout & Portal

Ref: discovery/02 secao Billing/Checkout

- [ ] Escrever testes para contexto `Blackboex.Billing`:
  - `create_checkout_session/2` chama Stripe e retorna URL (mock Stripe)
  - `create_portal_session/1` retorna URL do portal (mock Stripe)
  - `get_subscription/1` retorna subscription da org
  - `sync_subscription/1` atualiza banco com dados do Stripe
- [ ] Implementar contexto `Blackboex.Billing` (com Mox para Stripe em testes)
- [ ] Escrever testes LiveView para `BlackboexWeb.BillingLive.Plans`:
  - Mostra 3 cards de planos com features
  - Plano atual destacado
  - Botao "Escolher plano" presente
- [ ] Implementar LiveView `BlackboexWeb.BillingLive.Plans`
- [ ] Escrever testes LiveView para `BlackboexWeb.BillingLive.Manage`:
  - Mostra status da assinatura
  - Botao "Gerenciar" presente
- [ ] Implementar LiveView `BlackboexWeb.BillingLive.Manage`
- [ ] Verificar: checkout e portal funcionam (Stripe test mode)

## 3. Webhooks Stripe

Ref: discovery/02 secao Webhooks

- [ ] Criar migration para tabela `processed_stripe_events`:
  - `id` (UUID), `event_id` (string, unique), `event_type`, `processed_at`
  - Unique index em `event_id` para idempotencia
- [ ] Escrever testes para `BlackboexWeb.WebhookController`:
  - Assinatura invalida retorna 400
  - Evento delegado ao handler correto
  - Evento duplicado (mesmo event_id em `processed_stripe_events`) e idempotente
- [ ] Escrever testes para `Blackboex.Billing.WebhookHandler`:
  - `handle_event("checkout.session.completed", payload)` cria/atualiza subscription
  - `handle_event("customer.subscription.updated", payload)` sync plan/status
  - `handle_event("customer.subscription.deleted", payload)` marca canceled
  - `handle_event("invoice.payment_failed", payload)` marca past_due
- [ ] Implementar `BlackboexWeb.WebhookController` com verificacao de assinatura e lookup em `processed_stripe_events`
- [ ] Implementar `Blackboex.Billing.WebhookHandler` — modulo dedicado com funcoes `handle_event/2` para cada tipo
- [ ] Verificar: webhooks processam corretamente

## 4. Usage Tracking

Ref: discovery/02 secao Usage/Metering

- [ ] Escrever testes para schema `Blackboex.Billing.UsageEvent`:
  - Changeset valido com org_id, event_type, metadata, timestamp
  - event_type validos: "api_invocation", "llm_generation"
- [ ] Criar migration para tabela `usage_events`:
  - `id` (UUID), `organization_id`, `event_type`, `metadata` (jsonb), `inserted_at`
  - Index em `[:organization_id, :inserted_at]`
  - Fonte granular de dados por request (dados brutos para agregar em DailyUsage)
- [ ] Implementar schema `Blackboex.Billing.UsageEvent`
- [ ] Escrever testes para schema `Blackboex.Billing.DailyUsage`:
  - Changeset valido com org_id, date, contadores
  - Unique org_id + date
- [ ] Criar migration para tabela `daily_usage`:
  - `id` (UUID), `organization_id`, `date`, `api_invocations`,
    `llm_generations`, `tokens_input`, `tokens_output`, `llm_cost_cents`
  - unique index `[:organization_id, :date]`
  - Nota: `apis_count` NAO incluido — total de APIs e cumulativo, consultar diretamente da tabela `apis`
- [ ] Implementar schema `Blackboex.Billing.DailyUsage`
- [ ] Escrever testes para Oban worker `Blackboex.Billing.UsageAggregationWorker`:
  - Agrega `usage_events` do dia anterior em `daily_usage`
  - Idempotente (re-executar nao duplica)
- [ ] Implementar worker Oban para agregacao diaria
- [ ] Verificar: `mix test` passa com testes de usage tracking

## 5. Enforcement

Ref: discovery/02 secao Enforcement/Limites

> **Pre-requisito:** Depende de modulos das Fases 02, 03 e 07 — `Blackboex.CodeGen.Pipeline` (LLM),
> `Blackboex.Apis` (criacao de APIs), `BlackboexWeb.Plugs.DynamicApiRouter` (invocacoes).
> Implementar enforcement APOS esses modulos existirem.

- [ ] Escrever testes para `Blackboex.Billing.Enforcement`:
  - Free: 10 APIs, 1000 invocacoes/dia, 50 geracoes LLM/mes
  - Pro: 50 APIs, 50k invocacoes/dia, 500 geracoes/mes
  - Enterprise: ilimitado
  - `check_limit/2` retorna `{:ok, remaining}` dentro do limite
  - `check_limit/2` retorna `{:error, :limit_exceeded, details}` acima do limite
  - Contagem de APIs consulta `Blackboex.Apis` (nao `daily_usage`)
- [ ] Implementar `Blackboex.Billing.Enforcement`
- [ ] Integrar enforcement nos pontos de controle especificos:
  - `Blackboex.CodeGen.Pipeline` — antes de gerar codigo LLM
  - `Blackboex.Apis` — antes de criar API
  - `BlackboexWeb.Plugs.DynamicApiRouter` — no gateway (invocacoes)
- [ ] Resposta 402 com link para upgrade
- [ ] Verificar: limites enforced por plano

## 6. Rotas

Ref: discovery/02 secao Rotas/Router

- [ ] Configurar rotas no router para todos os novos escopos:
  - `/billing/*` — LiveViews de planos e gerenciamento (autenticado)
  - `/admin/*` — Backpex admin (requer `is_platform_admin`)
  - `/webhooks/stripe` — WebhookController (sem auth, com verificacao de assinatura)
- [ ] Verificar: todas as rotas respondem corretamente

## 7. Admin - Platform Admin Flag

Ref: discovery/02 secao Admin/Autorizacao

- [ ] Escrever testes para migration `is_platform_admin`:
  - Campo booleano default false na tabela `users`
  - Platform admin e diferente de org owner (admin da plataforma, nao da organizacao)
- [ ] Criar migration: `add :is_platform_admin, :boolean, default: false` na tabela `users`
- [ ] Atualizar schema `Blackboex.Accounts.User` com campo `is_platform_admin`
- [ ] Escrever testes para plug `BlackboexWeb.Plugs.RequirePlatformAdmin`:
  - Admin (`is_platform_admin: true`) acessa `/admin`
  - Org owner sem flag admin e redirecionado
  - Usuario normal redirecionado
- [ ] Implementar plug `BlackboexWeb.Plugs.RequirePlatformAdmin`

## 8. Painel Admin com Backpex

Ref: discovery/02 secao Backpex/Admin

- [ ] Adicionar `{:backpex, "~> 0.17"}` ao `mix.exs` de `blackboex_web`
- [ ] Configurar DaisyUI com escopo limitado ao `/admin` (Backpex requer DaisyUI, mas o projeto usa SaladUI/Tailwind). Opcoes:
  - CSS com escopo: DaisyUI carregado apenas dentro do layout admin
  - Alternativa: Backpex admin tera seu proprio escopo de estilo separado do app principal
- [ ] Criar layout `{BlackboexWeb.Layouts, :admin}` — layout dedicado para Backpex
- [ ] Configurar Backpex no router: `/admin` (com plug `RequirePlatformAdmin`)
- [ ] Criar LiveResource `BlackboexWeb.Admin.UserLive`:
  - Campos: email, name, is_platform_admin, org count, inserted_at
  - `can?/3`: somente platform admin pode editar/desativar
- [ ] Criar LiveResource `BlackboexWeb.Admin.OrganizationLive`:
  - Campos: name, slug, member_count, subscription_plan, inserted_at
  - `can?/3`: platform admin pode editar, ninguem pode deletar
- [ ] Criar LiveResource `BlackboexWeb.Admin.ApiLive`:
  - Campos: name, organization, status, invocation_count, inserted_at
  - `can?/3`: platform admin pode desativar
- [ ] Criar LiveResource `BlackboexWeb.Admin.SubscriptionLive`:
  - Campos: organization, plan, status, stripe_customer_id, current_period_end
  - `can?/3`: somente leitura
- [ ] Criar LiveResource `BlackboexWeb.Admin.InvocationLogLive`:
  - Campos: api_name, status_code, duration_ms, inserted_at
  - `can?/3`: somente leitura, com filtros por data e API
- [ ] Criar LiveResource `BlackboexWeb.Admin.LlmUsageLive`:
  - Campos: organization, model, tokens_input, tokens_output, cost_cents, inserted_at
  - `can?/3`: somente leitura
- [ ] Dashboard admin com stats (usuarios, APIs, invocacoes)
- [ ] Verificar: admin navega e gerencia recursos

## 9. Audit Logging - ExAudit (Row-Level)

Ref: discovery/02 secao Audit/ExAudit

ExAudit rastreia mudancas em nivel de row automaticamente (quem mudou o que, quando).

- [ ] Adicionar `{:ex_audit, "~> 0.10"}` ao `mix.exs` de `blackboex`
- [ ] Configurar ExAudit no Repo (`use ExAudit.Repo`)
- [ ] Gerar migration do ExAudit: `mix audit.gen` (cria tabelas de versioning)
- [ ] Implementar plug `BlackboexWeb.Plugs.AuditContext`:
  - Injeta `current_user` no Repo metadata para ExAudit rastrear o actor
  - Adicionar ao pipeline autenticado no router
- [ ] Configurar schemas que devem ser rastreados pelo ExAudit (subscriptions, apis, api_keys, organizations)
- [ ] Verificar: ExAudit registra versoes de mudancas com actor

## 10. Audit Logging - Custom Audit Logs (Operation-Level)

Ref: discovery/02 secao Audit/OperationLog

Audit logs customizados para operacoes de negocio (acoes explicitas do usuario).

- [ ] Escrever testes para `Blackboex.Audit`:
  - Publicar API gera audit log
  - Criar API key gera audit log
  - Revogar key gera audit log
  - Mudar plano gera audit log
  - Log contem: user_id, action, resource_type, resource_id, metadata
- [ ] Criar migration para tabela `audit_logs`:
  - `id` (UUID), `user_id`, `organization_id`, `action`, `resource_type`,
    `resource_id`, `metadata` (jsonb), `ip_address`
- [ ] Implementar schema e contexto `Blackboex.Audit` para registro de operacoes criticas
- [ ] Exibir audit log no admin (Backpex) e na pagina de settings
- [ ] Verificar: todas operacoes criticas geram log

## 11. Feature Flags

Ref: discovery/02 secao FeatureFlags

- [ ] Adicionar `{:fun_with_flags, "~> 1.0"}` ao `mix.exs` de `blackboex`
- [ ] Escrever testes para `Blackboex.Features`:
  - `enabled?/2` retorna true/false conforme flag
  - `enable/2` ativa flag
  - `disable/2` desativa flag
- [ ] Implementar `Blackboex.Features` com FunWithFlags (backend Ecto)
- [ ] Implementar protocols `FunWithFlags.Actor` e `FunWithFlags.Group`:
  - `FunWithFlags.Actor` para `Blackboex.Accounts.User` — avaliacao de flags por usuario
  - `FunWithFlags.Group` para avaliacao por plano (free/pro/enterprise) — flags habilitadas por tier
- [ ] Flags iniciais: `:custom_domains`, `:collaborative_editing`, `:load_testing`
- [ ] Integrar flags na UI (esconder features inativas)
- [ ] Interface de flags no admin
- [ ] Verificar: flags controlam visibilidade

## 12. Settings do Usuario

Ref: discovery/02 secao Settings/UI

- [ ] Escrever testes LiveView para `SettingsLive`:
  - Abas renderizam: Perfil, Organizacao, Chaves API, Billing, Seguranca
  - Editar nome funciona
  - Editar nome da org funciona
  - Membros listados com roles
- [ ] Implementar LiveView `SettingsLive` com abas SaladUI
- [ ] Verificar: todas as abas funcionais

## 13. Qualidade

- [ ] `mix format --check-formatted` passa
- [ ] `mix credo --strict` passa
- [ ] `mix dialyzer` passa
- [ ] `make precommit` passa
- [ ] `@spec` em todas as funcoes publicas

---

## Criterios de Aceitacao

- [ ] Pagina de planos com Stripe checkout
- [ ] Webhooks processam corretamente (test mode)
- [ ] Limites enforced por plano
- [ ] 402 com link para upgrade ao exceder limite
- [ ] Admin funcional com CRUD de recursos (somente platform admins)
- [ ] ExAudit rastreia mudancas row-level com actor
- [ ] Audit logs customizados registram operacoes criticas
- [ ] Feature flags controlam features (com Actor/Group protocols)
- [ ] Settings do usuario com abas: Perfil, Organizacao, Chaves API, Billing, Seguranca
- [ ] `make precommit` passa
- [ ] 100% TDD
