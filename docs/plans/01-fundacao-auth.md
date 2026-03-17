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

- [ ] Instalar componentes SaladUI: `mix salad.add button card dropdown_menu avatar badge separator sheet navigation_menu input label`
- [ ] Verificar: componentes SaladUI disponiveis para uso nos templates

## 2. Autenticacao com phx.gen.auth (Magic Link)

Ref: `docs/discovery/02-backoffice-config.md` (auth, Scope struct)

- [ ] Criar migration para extensao `citext` (antes da tabela users)
- [ ] Executar `mix phx.gen.auth Accounts User users` no app web
- [ ] Verificar que phx.gen.auth gerou contexts em `apps/blackboex/` gracas a `generators: [context_app: :blackboex]` em `config.exs`. Verificar estrutura: Accounts context + User schema + UserToken schema + Scope struct em `apps/blackboex/`, UserAuth plugs + controllers/LiveViews em `apps/blackboex_web/`
- [ ] Escrever testes para contexto `Blackboex.Accounts`: `@tag :unit`
  - `register_user/1` cria usuario com email valido
  - `register_user/1` falha com email invalido
  - `get_user_by_email/1` retorna user correto
  - `generate_user_session_token/1` gera token de sessao
  - `get_user_by_session_token/1` retorna user correto
- [ ] Ajustar contexto `Blackboex.Accounts` se necessario (phx.gen.auth gera base)
- [ ] Configurar Swoosh: `Swoosh.Adapters.Local` para dev, `Swoosh.Adapters.Test` para test
- [ ] Verificar: rota `/dev/mailbox` funciona em dev
- [ ] Adaptar templates de auth para Tailwind + SaladUI (componentes ja instalados na secao 1)
- [ ] Verificar: testes de registro, login (magic link), logout passam

## 3. Schemas Base: Organization, Membership

Ref: `docs/discovery/02-backoffice-config.md` (schemas base, multi-tenancy)

> **Nota:** User schema ja foi gerado pelo `phx.gen.auth` na secao anterior.

- [ ] Escrever testes para schema `Blackboex.Organizations.Organization`: `@tag :unit`
  - Changeset valido com name + slug
  - Slug gerado automaticamente a partir do name
  - Slug unique
  - Plan default `:free`
- [ ] Criar migration + schema `Organization` (UUID pk, name, slug unique, plan com `Ecto.Enum, values: [:free, :pro, :enterprise], default: :free`)
- [ ] Escrever testes para schema `Blackboex.Organizations.Membership`: `@tag :unit`
  - Changeset valido com user_id + org_id + role
  - Roles validos: `:owner`, `:admin`, `:member` (via `Ecto.Enum, values: [:owner, :admin, :member]`)
  - Unique constraint user_id + org_id
- [ ] Criar migration + schema `Membership` (UUID pk, user_id, organization_id, role com Ecto.Enum)
- [ ] Verificar: `make test` passa com todos os testes de schema

## 4. Organizacoes & Multi-tenancy

Ref: `docs/discovery/02-backoffice-config.md` (multi-tenancy, org pessoal)

- [ ] Escrever testes para contexto `Blackboex.Organizations`: `@tag :unit`
  - `create_organization/2` cria org e membership owner atomicamente
  - `list_user_organizations/1` retorna orgs do usuario
  - `get_organization!/1` retorna org por id
  - `add_member/3` adiciona membro com role
  - `add_member/3` falha se ja for membro
- [ ] Implementar contexto `Blackboex.Organizations`
- [ ] Escrever teste: ao registrar usuario, org pessoal e criada automaticamente `@tag :unit`
- [ ] Implementar hook no `Accounts.register_user/1` que cria org pessoal
- [ ] Escrever testes para `BlackboexWeb.Hooks.SetOrganization` (on_mount para LiveViews): `@tag :liveview`
  - Carrega org_id da sessao
  - Carrega org + membership do usuario
  - Fallback para primeira org do usuario se nenhuma na sessao
- [ ] Implementar on_mount `BlackboexWeb.Hooks.SetOrganization` para LiveViews
- [ ] Escrever testes para plug `BlackboexWeb.Plugs.SetOrganization` (para controllers): `@tag :unit`
  - Mesma logica: sessao -> org_id -> load org + membership -> fallback primeira org
- [ ] Implementar plug `BlackboexWeb.Plugs.SetOrganization` para controllers
- [ ] Escrever testes para extensao do Scope: `@tag :unit`
  - Scope inclui organization e membership alem de user
- [ ] Estender Scope struct para incluir `organization` e `membership`
- [ ] Verificar: `make test` passa

## 5. RBAC com LetMe

Ref: `docs/discovery/02-backoffice-config.md` (RBAC, permissoes)

- [ ] Adicionar `let_me ~> 1.2` ao `mix.exs` do app dominio
- [ ] Escrever testes para `Blackboex.Policy` com `Blackboex.Policy.Checks`: `@tag :unit`
  - Owner pode :manage (qualquer acao) em qualquer recurso da org
  - Admin pode :create, :read, :update, :delete em Organization e Membership
  - Member pode :read em Organization; :read em Membership
  - Nenhum role acessa recursos de outra org
  - Testar permissoes sobre Organization e Membership (APIs nao existem nesta fase)
- [ ] Implementar modulo `Blackboex.Policy` com `Blackboex.Policy.Checks` usando regras LetMe
- [ ] Escrever teste para plug `BlackboexWeb.Plugs.Authorize`: `@tag :unit`
- [ ] Implementar plug de autorizacao
- [ ] Verificar: testes de RBAC passam, permissoes corretas por role

## 6. Layout & Dashboard

Ref: `docs/discovery/02-backoffice-config.md` (layout, dashboard)

- [ ] Escrever teste LiveView para `DashboardLive`: `@tag :liveview`
  - Usuario logado ve pagina de dashboard
  - Dashboard mostra mensagem de boas-vindas
  - Dashboard mostra botao "Criar API"
  - Usuario nao logado e redirecionado para login
- [ ] Implementar layout principal:
  - Header: logo, org switcher, user menu
  - Sidebar: navegacao (Dashboard, APIs, Settings)
  - Content area
- [ ] Implementar LiveView `DashboardLive` com:
  - Mensagem de boas-vindas
  - Card "Nenhuma API criada ainda" com botao "Criar API"
- [ ] Escrever teste LiveView para org switcher: `@tag :liveview`
- [ ] Implementar org switcher no header (dropdown SaladUI)
- [ ] Verificar: apos login, usuario ve dashboard completo

## 7. Qualidade

- [ ] `mix format --check-formatted` passa
- [ ] `mix credo --strict` passa
- [ ] `mix dialyzer` passa
- [ ] Todos os testes passam com `make test`
- [ ] `make precommit` passa integralmente
- [ ] Cobertura de testes: todos os contextos e schemas testados
- [ ] `@spec` em todas as funcoes publicas dos contextos e schemas

---

## Criterios de Aceitacao

- [ ] Usuario se registra com email (magic link)
- [ ] Usuario faz login e ve dashboard
- [ ] Organizacao pessoal criada automaticamente no registro
- [ ] Org switcher funciona no header
- [ ] RBAC basico funciona (owner/admin/member com permissoes distintas)
- [ ] Layout com header, sidebar, content area
- [ ] `make precommit` passa (compile + format + test)
- [ ] Todos os testes escritos ANTES da implementacao (TDD)
