# FlowSecrets — Encrypted credentials for flow execution

## Overview

`Blackboex.FlowSecrets` stores named secret values (API keys, passwords, tokens) scoped to an organization and project, making them available to the flow execution engine at runtime without exposing plaintext values in flow definitions. The current "encryption" is Base64 encoding — a placeholder for Cloak-based encryption in a future iteration.

## Modules

### `Blackboex.FlowSecrets` (`lib/blackboex/flow_secrets.ex`)
Public facade. All callers go through this module only.

### `Blackboex.FlowSecrets.FlowSecret` (`lib/blackboex/flow_secrets/flow_secret.ex`)
Ecto schema for a stored secret.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `binary_id` | UUID primary key |
| `name` | `string` | Identifier used to reference the secret in flows. Must match `^[a-zA-Z0-9_]+$` |
| `encrypted_value` | `binary` | Base64-encoded secret value (never stored or logged as plaintext) |
| `organization_id` | `binary_id` FK | Owning organization |
| `project_id` | `binary_id` FK | Owning project |

Unique constraint: `(project_id, name)` — secret names are unique within a project.

### `Blackboex.FlowSecrets.FlowSecretQueries` (`lib/blackboex/flow_secrets/flow_secret_queries.ex`)
Query builders only — no `Repo` calls, no side effects.

| Function | Description |
|----------|-------------|
| `list_for_org/1` | All secrets for an organization, ordered by name |
| `by_org_and_name/2` | Single secret by org + name |
| `list_for_project/1` | All secrets for a project, ordered by name |

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `list_secrets/1` | `(organization_id)` | `[FlowSecret.t()]` | All secrets for an org (returns structs with encrypted values, not plaintext) |
| `list_secrets_for_project/1` | `(project_id)` | `[FlowSecret.t()]` | All secrets for a project |
| `get_secret/2` | `(organization_id, name)` | `FlowSecret.t() \| nil` | Lookup by org + name |
| `get_secret_value/2` | `(organization_id, name)` | `{:ok, String.t()} \| {:error, :not_found}` | Decodes and returns the plaintext value — use only in execution engine |
| `create_secret/1` | `(attrs)` | `{:ok, FlowSecret.t()}` | Creates a secret; pass `value` (plaintext) in attrs — it is encoded before insert |
| `update_secret/2` | `(secret, attrs)` | `{:ok, FlowSecret.t()}` | Updates name or value; pass `value` (plaintext) in attrs |
| `delete_secret/1` | `(secret)` | `{:ok, FlowSecret.t()}` | Hard deletes the secret |

## How Secrets Are Resolved at Runtime

Flow nodes reference secrets by name (e.g. `{{secrets.OPENAI_KEY}}`). The execution engine calls `get_secret_value/2` with the org ID and secret name to retrieve the plaintext value at execution time. The plaintext value is used only in memory during execution and is never written back to the database or included in `FlowExecution.output`.

## Security Invariants

- **Never log plaintext secret values** — `encrypted_value` holds an encoded binary; never log or return `FlowSecret.decrypt_value/1` output in error messages or audit logs
- **Never store plaintext** — always pass the raw value as `value` in attrs; the changeset encodes it via `maybe_encrypt_value/2` before writing to `encrypted_value`
- Secret names must be `[a-zA-Z0-9_]+` — validated in the changeset, preventing injection via interpolation in flow templates
- `get_secret_value/2` is for the execution engine only — never call this from LiveView or controllers to return to the browser
- Unique constraint on `(project_id, name)` prevents duplicate secrets silently overriding each other
