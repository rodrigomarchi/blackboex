# Samples Context

`Blackboex.Samples.Manifest` is the single source of truth for platform samples/templates.

## Rules

- Add API, Flow, Page, and Playground examples through `Blackboex.Samples.*`.
- API template payload modules live under `Blackboex.Samples.ApiTemplates.*`.
- Flow template payload modules live under `Blackboex.Samples.FlowTemplates.*`.
- Do not add parallel sample lists in seeds, UI components, or context modules.
- `sample_uuid` is stable identity. Do not change it for the same logical sample.
- `Apis.Templates` and `Flows.Templates` are compatibility adapters over the manifest.
- Managed workspace sync updates records by `sample_uuid` and ignores user-created records without `sample_uuid`.
