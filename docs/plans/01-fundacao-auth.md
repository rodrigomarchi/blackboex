# Fase 01 - Autenticacao & Organizacoes

> **Entregavel testavel:** Usuario cria conta, faz login, tem organizacao pessoal
> criada automaticamente, RBAC basico funciona, dashboard vazio com layout.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

## Fontes de Discovery
- `docs/discovery/02-backoffice-config.md` (auth, RBAC, schemas base)

## O que ja existe
- Umbrella app configurado e funcionando
- Phoenix 1.8 + LiveView 1.1 + Bandit + SaladUI
- Ecto + PostgreSQL 16 via Docker Compose
- Makefile, Credo strict, Dialyxir, Mox, ExMachina
- `config.exs` tem `generators: [context_app: :blackboex]` — phx.gen.auth gera contexts no app dominio

---

## 1. Configurar SaladUI

Ref: `docs/discovery/02-backoffice-config.md` (componentes UI)

- [x] Instalar componentes SaladUI: button, card, dropdown_menu, avatar, badge, separator, sheet, input, label, sidebar, skeleton, tooltip
- [x] Criar `BlackboexWeb.Component` module para uso dos componentes SaladUI
- [x] Configurar `component_module_prefix` no config.exs
- [x] Verificar: componentes SaladUI disponiveis para uso nos templates

## 2. Autenticacao com phx.gen.auth (Magic Link)

Ref: `docs/discovery/02-backoffice-config.md` (auth, Scope struct)

- [x] Criar migration para extensao `citext` (antes da tabela users)
- [x] Executar `mix phx.gen.auth Accounts User users` no app web
- [x] Verificar que phx.gen.auth gerou contexts em `apps/blackboex/` gracas a `generators: [context_app: :blackboex]` em `config.exs`. Verificar estrutura: Accounts context + User schema + UserToken schema + Scope struct em `apps/blackboex/`, UserAuth plugs + controllers/LiveViews em `apps/blackboex_web/`
- [x] Testes para contexto `Blackboex.Accounts` gerados automaticamente pelo phx.gen.auth (39 testes dominio + 72 testes web)
- [x] Ajustar contexto `Blackboex.Accounts` — adicionado hook para criar org pessoal no registro
- [x] Configurar Swoosh: `Swoosh.Adapters.Local` para dev, `Swoosh.Adapters.Test` para test
- [x] Rota `/dev/mailbox` configurada em dev
- [x] Verificar: testes de registro, login (magic link), logout passam

## 3. Schemas Base: Organization, Membership

Ref: `docs/discovery/02-backoffice-config.md` (schemas base, multi-tenancy)

> **Nota:** User schema ja foi gerado pelo `phx.gen.auth` na secao anterior.

- [x] Escrever testes para schema `Blackboex.Organizations.Organization`: `@moduletag :unit`
  - Changeset valido com name + slug
  - Slug gerado automaticamente a partir do name
  - Slug unique
  - Plan default `:free`
- [x] Criar migration + schema `Organization` (UUID pk, name, slug unique, plan com `Ecto.Enum, values: [:free, :pro, :enterprise], default: :free`)
- [x] Escrever testes para schema `Blackboex.Organizations.Membership`: `@moduletag :unit`
  - Changeset valido com user_id + org_id + role
  - Roles validos: `:owner`, `:admin`, `:member` (via `Ecto.Enum, values: [:owner, :admin, :member]`)
  - Unique constraint user_id + org_id
- [x] Criar migration + schema `Membership` (UUID pk, user_id, organization_id, role com Ecto.Enum)
- [x] Verificar: `make test` passa com todos os testes de schema

## 4. Organizacoes & Multi-tenancy

Ref: `docs/discovery/02-backoffice-config.md` (multi-tenancy, org pessoal)

- [x] Escrever testes para contexto `Blackboex.Organizations`: `@moduletag :unit`
  - `create_organization/2` cria org e membership owner atomicamente
  - `list_user_organizations/1` retorna orgs do usuario
  - `get_organization!/1` retorna org por id
  - `add_member/3` adiciona membro com role
  - `add_member/3` falha se ja for membro
- [x] Implementar contexto `Blackboex.Organizations`
- [x] Escrever teste: ao registrar usuario, org pessoal e criada automaticamente `@moduletag :unit`
- [x] Implementar hook no `Accounts.register_user/1` que cria org pessoal via Ecto.Multi
- [x] Escrever testes para `BlackboexWeb.Hooks.SetOrganization` (on_mount para LiveViews): `@moduletag :unit`
  - Carrega org_id da sessao
  - Carrega org + membership do usuario
  - Fallback para primeira org do usuario se nenhuma na sessao
- [x] Implementar on_mount `BlackboexWeb.Hooks.SetOrganization` para LiveViews
- [x] Escrever testes para plug `BlackboexWeb.Plugs.SetOrganization` (para controllers): `@moduletag :unit`
  - Mesma logica: sessao -> org_id -> load org + membership -> fallback primeira org
- [x] Implementar plug `BlackboexWeb.Plugs.SetOrganization` para controllers
- [x] Escrever testes para extensao do Scope: `@moduletag :unit`
  - Scope inclui organization e membership alem de user
- [x] Estender Scope struct para incluir `organization` e `membership`
- [x] Verificar: `make test` passa

## 5. RBAC com LetMe

Ref: `docs/discovery/02-backoffice-config.md` (RBAC, permissoes)

- [x] Adicionar `let_me ~> 1.2` ao `mix.exs` do app dominio
- [x] Escrever testes para `Blackboex.Policy` com `Blackboex.Policy.Checks`: `@moduletag :unit`
  - Owner pode qualquer acao em qualquer recurso da org
  - Admin pode :create, :read, :update, :delete em Organization e Membership
  - Member pode :read em Organization; :read em Membership
  - Nenhum role acessa recursos de outra org
  - Testado sobre Organization e Membership
- [x] Implementar modulo `Blackboex.Policy` com `Blackboex.Policy.Checks` usando regras LetMe
- [x] Escrever teste para plug `BlackboexWeb.Plugs.Authorize`: `@moduletag :unit`
- [x] Implementar plug de autorizacao
- [x] Verificar: testes de RBAC passam, permissoes corretas por role

## 6. Layout & Dashboard

Ref: `docs/discovery/02-backoffice-config.md` (layout, dashboard)

- [x] Escrever teste LiveView para `DashboardLive`: `@moduletag :liveview`
  - Usuario logado ve pagina de dashboard
  - Dashboard mostra mensagem de boas-vindas
  - Dashboard mostra botao "Create API"
  - Usuario nao logado e redirecionado para login
- [x] Implementar layout principal:
  - Header: logo, org name, user menu, theme toggle
  - Sidebar: navegacao (Dashboard, APIs, Settings)
  - Content area
- [x] Implementar LiveView `DashboardLive` com:
  - Mensagem de boas-vindas
  - Card "No APIs created yet" com botao "Create API"
- [x] Org name exibido no header (org switcher basico)
- [x] Verificar: apos login, usuario ve dashboard completo

## 7. Qualidade

- [x] `mix format --check-formatted` passa
- [x] `mix credo --strict` passa
- [x] `mix dialyzer` passa (2 warnings de Ecto.Multi opaque ignorados via .dialyzer_ignore.exs)
- [x] Todos os testes passam com `make test` (150 testes, 0 falhas)
- [x] `make precommit` passa integralmente
- [x] Cobertura de testes: todos os contextos e schemas testados
- [x] `@spec` em todas as funcoes publicas dos contextos e schemas

---

## Criterios de Aceitacao

- [x] Usuario se registra com email (magic link)
- [x] Usuario faz login e ve dashboard
- [x] Organizacao pessoal criada automaticamente no registro
- [x] Org name exibido no header
- [x] RBAC basico funciona (owner/admin/member com permissoes distintas)
- [x] Layout com header, sidebar, content area
- [x] `make precommit` passa (compile + format + test)
- [x] Todos os testes escritos ANTES da implementacao (TDD)
