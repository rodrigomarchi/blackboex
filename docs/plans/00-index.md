# BlackBoex - Planos de Implementacao

## Estado Atual do Projeto

O projeto ja esta bootstrapped com:

- Umbrella app: `apps/blackboex` (dominio) + `apps/blackboex_web` (web)
- Elixir 1.19.4 / OTP 28, Phoenix 1.8.3, LiveView 1.1, Bandit
- Ecto + PostgreSQL 16 (Docker Compose com DB dev + test)
- Tailwind 4, esbuild, SaladUI, Heroicons
- Credo strict, Dialyxir, Mox, ExMachina, Floki
- Makefile completo (setup, server, test, lint, precommit, etc)

## Metodologia: TDD

**Todo codigo novo segue TDD rigoroso:**

1. **Red** — Escrever o teste primeiro. O teste DEVE falhar.
2. **Green** — Escrever a implementacao minima para o teste passar.
3. **Refactor** — Melhorar o codigo mantendo os testes verdes.

Cada tarefa nos planos comeca por "Escrever teste para X" seguido de "Implementar X".
Os testes sao a especificacao executavel do comportamento esperado.

Tags de teste: `@tag :unit`, `@tag :integration`, `@tag :liveview`

## Visao Geral das Fases

| Fase | Nome | Entregavel Testavel |
|------|------|---------------------|
| 01 | Auth & Organizacoes | Usuario cria conta, faz login, tem org pessoal, RBAC basico |
| 02 | LLM & Geracao de Codigo | Usuario descreve API em linguagem natural e recebe codigo Elixir |
| 03 | Compilacao & Execucao | Codigo gerado compila em sandbox e responde HTTP via rotas dinamicas |
| 04 | Editor & Versionamento | Usuario edita codigo no browser com Monaco, salva versoes |
| 05 | Edicao Conversacional | Usuario refina codigo via chat com LLM, ve diffs, aceita/rejeita |
| 06 | Teste Interativo | Usuario testa API no browser com request builder e historico |
| 07 | Publicacao | API publicada com URL publica, API key auth, rate limiting |
| 08 | Documentacao & Testes Auto | OpenAPI spec gerada, Swagger UI, testes auto-gerados pelo LLM |
| 09 | Billing & Admin | Stripe integrado, painel admin, audit logging |
| 10 | Observabilidade | Telemetria completa, dashboards Grafana, alertas, analytics por API |

## Dependencias entre Fases

```
01 Auth
 └─> 02 LLM
      └─> 03 Compilacao
           ├─> 04 Editor
           │    └─> 05 Chat Edit
           ├─> 06 Teste
           └─> 07 Publicacao
                └─> 08 Docs & Auto-Tests
09 Billing (depende de 01-07)
10 Observabilidade (instrumenta tudo)
```

## Como Usar os Planos

1. Cada plano e um arquivo `.md` com task list em formato checkbox
2. Ao executar um plano, **sempre atualize o progresso** marcando tarefas como `[x]`
3. Nao pule fases — cada uma depende das anteriores
4. Ao final de cada fase, execute os criterios de aceitacao antes de avancar
5. Siga TDD: teste primeiro, implementacao depois
