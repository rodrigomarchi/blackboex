# Samples Context

`Blackboex.Samples.Manifest` is the single source of truth for platform samples/templates.

## Current Inventory

| Kind | Count | Module |
|------|-------|--------|
| API | 19 | `Blackboex.Samples.Api` delegates to modules in `ApiTemplates.*` |
| Flow | 28 | `Blackboex.Samples.Flow` uses 27 `FlowTemplates.*` modules plus `echo_transform/0` |
| Page | 9 | `Blackboex.Samples.Page` contains one root plus eight end-user onboarding topics |
| Playground | 20 | `Blackboex.Samples.Playground` |

The current manifest version lives in `Blackboex.Samples.Manifest.@version`. Bump it whenever managed sample content changes. Workspace sync uses `(sample_uuid, sample_manifest_version)` to decide what to rewrite.

## Page Sample Tree

Page samples are English-only product onboarding content for end users. They must teach actions inside Blackboex, not the app's implementation or local toolchain.

```
welcome (Welcome to Blackboex, root)
├── apis              - Create Your First API
├── api_test_publish  - Test, Publish, and Call an API
├── flows             - Build a Visual Flow
├── flow_webhooks     - Receive Webhooks with Flows
├── playgrounds       - Experiment in Playgrounds
├── pages_doc         - Document Your Project with Pages
├── project_workflow  - Combine APIs, Flows, Pages, and Playgrounds
└── next_steps        - Next Steps
```

Each new Page onboarding topic should be a child of `welcome`. Use `topic/6` in `Samples.Page` to keep the structure consistent.

## Playground Categories

| Category | Examples |
|----------|----------|
| Elixir | enum_basics, pipe_operator, pattern_matching, with_clauses, comprehensions, map_keyword, streams_lazy, string_manipulation, date_time_math, regex_validatestion, range_basics, tuple_basics, errorr_handling, atom_safety |
| Blackboex | call_echo_flow, read_env_vars, http_get, http_post_json |
| Data | jason_parsing, base64_encoding |

Every Playground example must respect the `Blackboex.Playgrounds.Executor` sandbox: only allowlisted modules, no `File`, `System`, `:erlang`, `:os`, `defmodule`, or `Function.capture`.

## Rules

- Add API, Flow, Page, and Playground examples through `Blackboex.Samples.*`.
- API template payload modules live under `Blackboex.Samples.ApiTemplates.*`.
- Flow template payload modules live under `Blackboex.Samples.FlowTemplates.*`.
- Do not add parallel sample lists in seeds, UI components, or context modules.
- `sample_uuid` is stable identity. Do not change it for the same logical sample.
- `Apis.Templates` and `Flows.Templates` are compatibility adapters over the manifest.
- Managed workspace sync updates records by `sample_uuid` and ignores user-created records without `sample_uuid`.
- Page samples may set `parent_sample_uuid` to nest under another sample page, validatested by `Blackboex.Samples.ManifestTest`.
- Playground samples may set `flow_sample_uuid` so the `{{flow:UUID:webhook_token}}` placeholder is resolved during provisioning.
- Interpolation inside heredocs must be escaped as `\#{...}` when the literal text should survive compilation.
