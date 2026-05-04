# Samples Context

`Blackboex.Samples.Manifest` is the single source of truth for platform samples/templates.

## Inventário Atual

| Kind | Quantidade | Módulo |
|------|------------|--------|
| API | 19 | `Blackboex.Samples.Api` (delega aos módulos em `ApiTemplates.*`) |
| Flow | 28 | `Blackboex.Samples.Flow` (27 em `FlowTemplates.*` + `echo_transform/0`) |
| Page | 16 | `Blackboex.Samples.Page` (1 root + 13 tópicos + guia + sub-guia) |
| Playground | 20 | `Blackboex.Samples.Playground` |

A versão corrente do manifesto fica em `Blackboex.Samples.Manifest.@version`. Suba a versão sempre que mudar conteúdo de um sample existente — a sincronização do workspace usa `(sample_uuid, sample_manifest_version)` para decidir o que reescrever.

## Estrutura da Árvore de Pages

```
welcome (Bem-vindo ao Blackboex, root)
├── concepts          — Conceitos Fundamentais
├── apis              — APIs (geração com IA)
├── flows             — Flows (orquestração visual)
├── playgrounds       — Playgrounds (sandbox Elixir)
├── pages_doc         — Pages (documentação Markdown)
├── llms              — Integração com LLMs
├── conversations     — Conversations & Runs
├── telemetry         — Telemetria & Observabilidade
├── auth              — Autenticação & Multi-tenancy
├── audit             — Auditoria de Mudanças
├── feature_flags     — Feature Flags
├── testing           — Workflow de Testes
├── make_commands     — Comandos Make & Operação
├── roadmap           — Roadmap & Próximos Passos
└── formatting_guide  — Guia de Formatação
    └── elixir_patterns — Padrões de Código Elixir
```

Cada novo tópico de plataforma deve virar uma page filha de `welcome`. Use `topic/5` em `Samples.Page` para manter a estrutura consistente.

## Categorias de Playground

| Categoria | Exemplos |
|-----------|----------|
| Elixir | enum_basics, pipe_operator, pattern_matching, with_clauses, comprehensions, map_keyword, streams_lazy, string_manipulation, date_time_math, regex_validation, range_basics, tuple_basics, error_handling, atom_safety |
| Blackboex | call_echo_flow, read_env_vars, http_get, http_post_json |
| Dados | jason_parsing, base64_encoding |

Todo exemplo de Playground deve respeitar o sandbox do `Blackboex.Playgrounds.Executor`: somente módulos do allowlist (sem `File`, `System`, `:erlang`, `:os`, `defmodule`, `Function.capture`).

## Rules

- Add API, Flow, Page, and Playground examples through `Blackboex.Samples.*`.
- API template payload modules live under `Blackboex.Samples.ApiTemplates.*`.
- Flow template payload modules live under `Blackboex.Samples.FlowTemplates.*`.
- Do not add parallel sample lists in seeds, UI components, or context modules.
- `sample_uuid` is stable identity. Do not change it for the same logical sample.
- `Apis.Templates` and `Flows.Templates` are compatibility adapters over the manifest.
- Managed workspace sync updates records by `sample_uuid` and ignores user-created records without `sample_uuid`.
- Page samples may set `parent_sample_uuid` to nest under another sample page (validated by `Blackboex.Samples.ManifestTest`).
- Playground samples may set `flow_sample_uuid` para fazer placeholder `{{flow:UUID:webhook_token}}` ser resolvido em tempo de provisionamento.
- Strings com interpolação dentro de heredocs `"""..."""` precisam de `\#{...}` para sobreviver à compilação — caso contrário viram interpolação Elixir.
