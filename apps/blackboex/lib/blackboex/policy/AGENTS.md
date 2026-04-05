# Policy Context — Authorization via LetMe DSL

## Overview

`Blackboex.Policy` is the single authorization gateway for the entire application. It is built on the **LetMe** library, which provides a declarative DSL for defining role-based access control (RBAC) policies. Every protected mutation — create, delete, publish, rotate a key, etc. — must pass through this module before the domain context executes the work.

The policy layer is purely a **pre-check** gate. It answers "is this scope allowed to perform this action on this type of object?" before any database work happens. It does not perform post-fetch ownership checks (those belong in context queries) but it does validate that the caller's membership role permits the action.

Files in this directory:

| File | Purpose |
|---|---|
| `checks.ex` | Check functions referenced by `allow` clauses in `Policy` |
| `AGENTS.md` | This file |

The main policy module lives one level up at `apps/blackboex/lib/blackboex/policy.ex`.

---

## LetMe DSL

`Blackboex.Policy` calls `use LetMe.Policy`, which generates a public `authorize/3` function and supporting introspection helpers at compile time.

### Syntax

```elixir
object :resource_name do
  action :action_name do
    allow check_name: check_argument
    allow check_name: check_argument
  end
end
```

- `object` groups a set of actions under a logical resource name (`:organization`, `:api`, `:api_key`, `:membership`).
- `action` names a specific operation within that object.
- `allow` specifies one check that, if it returns `true`, grants access. Multiple `allow` clauses are **OR-ed**: access is granted if any single clause passes.
- Check functions are looked up by name in `Blackboex.Policy.Checks`. The clause `allow role: :owner` calls `Checks.role(scope, object, :owner)`.

### Generated `authorize/3`

```elixir
@spec authorize(atom(), Scope.t(), term()) :: :ok | {:error, :unauthorized}
Policy.authorize(action_atom, scope, object)
```

`action_atom` is the **compound atom** formed by joining the object name and action name with an underscore: `:api_delete`, `:api_key_create`, `:membership_update`, etc. See Action Naming Convention below.

---

## Checks Module

`Blackboex.Policy.Checks` contains every check function that the `allow` clauses delegate to. Currently there is one check: `role/3`.

### `role/3`

```elixir
@spec role(Scope.t(), Organization.t(), atom()) :: boolean()
def role(%Scope{membership: membership, organization: org}, %Organization{id: obj_org_id}, role)
```

**What it verifies — three conditions must all be true:**

1. `membership` is not `nil` — the caller has an active membership loaded on the scope.
2. `org.id == obj_org_id` — the scope's current organization matches the organization being acted upon (the FK pin match). This prevents cross-tenant authorization.
3. `membership.role == role` — the membership role equals the expected role atom (`:owner`, `:admin`, or `:member`).

**Fallback clause:** any call where the scope or object do not pattern-match the expected structs returns `false`, so missing or malformed scopes always deny.

The FK pin match (`org.id == obj_org_id`) is critical. If a user somehow presents a scope for org A and passes an org B struct as the object, the check returns `false`. Never skip this guard when extending the check.

---

## All Defined Policies

### `:organization`

| Action | Allowed Roles |
|---|---|
| `create` | owner, admin |
| `read` | owner, admin, member |
| `update` | owner, admin |
| `delete` | owner, admin |

### `:api`

| Action | Allowed Roles |
|---|---|
| `create` | owner, admin, member |
| `read` | owner, admin, member |
| `update` | owner, admin, member |
| `delete` | owner, admin |
| `publish` | owner, admin |
| `unpublish` | owner, admin |
| `generate_tests` | owner, admin, member |
| `run_tests` | owner, admin, member |
| `generate_docs` | owner, admin, member |

### `:api_key`

| Action | Allowed Roles |
|---|---|
| `create` | owner, admin |
| `revoke` | owner, admin |
| `rotate` | owner, admin |

### `:membership`

| Action | Allowed Roles |
|---|---|
| `create` | owner, admin |
| `read` | owner, admin, member |
| `update` | owner, admin |
| `delete` | owner, admin |

---

## Action Naming Convention

LetMe generates the action atom by combining `object_name` + `_` + `action_name`.

```
:organization_create
:organization_read
:organization_update
:organization_delete
:api_create
:api_read
:api_update
:api_delete
:api_publish
:api_unpublish
:api_generate_tests
:api_run_tests
:api_generate_docs
:api_key_create
:api_key_revoke
:api_key_rotate
:membership_create
:membership_read
:membership_update
:membership_delete
```

Always use the full compound atom. There is no shorthand. Passing `:delete` instead of `:api_delete` will result in `{:error, :unauthorized}` for every caller because no policy matches the bare atom.

---

## `authorize` vs `authorize_and_track`

### `Policy.authorize/3`

The raw LetMe-generated function. Returns `:ok` or `{:error, :unauthorized}`. Emits no side effects.

Use when:
- Writing tests — avoid polluting telemetry in test scenarios.
- Inside domain contexts where the caller is always trusted infrastructure (e.g., cron workers that act on behalf of the system, not a user scope).

### `Policy.authorize_and_track/3`

A thin wrapper defined manually in `policy.ex`:

```elixir
@spec authorize_and_track(atom(), Scope.t(), term()) :: :ok | {:error, :unauthorized}
def authorize_and_track(action, scope, object)
```

On success, returns `:ok` with no extra work. On failure, it:
1. Extracts `user_id` from `scope.user.id` (or `nil` if the scope is malformed).
2. Calls `Blackboex.Telemetry.Events.emit_policy_denied/1`, which fires a `[:blackboex, :policy, :denied]` telemetry event with `%{action: action, user_id: user_id}` metadata.
3. Returns `{:error, :unauthorized}`.

Use when:
- In LiveView `handle_event` callbacks — all user-initiated mutations use this.
- In controller actions that perform writes.
- Anywhere a denied authorization should be observable in metrics/alerting.

The telemetry event is intentionally low-cost (non-blocking, fire-and-forget via `safe_execute`). It is safe to call in every hot path.

---

## How to Add a New Policy

### Step 1 — Add the object/action block to `policy.ex`

```elixir
object :billing do
  action :update do
    allow role: :owner
  end
end
```

This generates the atom `:billing_update`.

### Step 2 — Decide if existing checks cover the case

The current `role/3` check in `Checks` handles all role-based decisions. If your new action has non-role conditions (e.g., "only the API owner" meaning the user who created it), add a new check function to `Checks`:

```elixir
@spec api_owner(Scope.t(), Api.t(), any()) :: boolean()
def api_owner(%Scope{user: %{id: user_id}}, %Api{user_id: api_user_id}, _), do:
  user_id == api_user_id
def api_owner(_, _, _), do: false
```

Then reference it in the policy:

```elixir
action :archive do
  allow role: :owner
  allow role: :admin
  allow api_owner: nil
end
```

The third argument to a check function is the value after the colon in the `allow` clause (`nil` above).

### Step 3 — Call `authorize_and_track` in the LiveView or context

```elixir
with :ok <- Policy.authorize_and_track(:billing_update, scope, org) do
  # perform work
else
  {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
end
```

The `object` passed as the third argument must be the struct that `Checks.role/3` expects — currently `%Organization{}`. Pass `scope.organization` for all current policies.

### Step 4 — Write a test (see Testing section below)

---

## Integration — Where Policy Is Called

### LiveViews

Policy is called directly inside `handle_event/3` callbacks, never in `mount/3`. The pattern is always:

```elixir
scope = socket.assigns.current_scope
org   = scope.organization

with :ok <- Policy.authorize_and_track(:action_atom, scope, org) do
  # domain call
else
  {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
end
```

Current call sites:

| LiveView | Action |
|---|---|
| `ApiLive.Index` | `:api_delete`, `:api_create` |
| `ApiKeyLive.Index` | `:api_key_create` |
| `ApiKeyLive.Show` | `:api_key_revoke`, `:api_key_rotate` |

### Scope Loading

`Blackboex.Accounts.Scope` carries `user`, `organization`, and `membership`. The `SetOrganization` on_mount hook populates `organization` and `membership` from the session before any LiveView mounts. This means `scope.organization` and `scope.membership` are always loaded (or `nil` if the user has no org) by the time `handle_event` fires.

The policy check fails gracefully when `membership` is `nil` — the fallback clause in `Checks.role/3` returns `false` for any pattern that does not match the full struct.

### Plugs and Controllers

There are no plug-level policy calls currently. If adding a REST controller action that writes data, call `Policy.authorize_and_track/3` at the top of the controller action, before any Ecto work.

---

## Testing

Use `Policy.authorize/3` (not `authorize_and_track`) in tests to avoid telemetry side effects.

### Minimal test structure

```elixir
defmodule Blackboex.PolicyTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Policy
  alias Blackboex.Accounts.Scope
  alias Blackboex.Factory

  describe "api_delete" do
    test "owner can delete" do
      {scope, org} = build_scope(:owner)
      assert :ok = Policy.authorize(:api_delete, scope, org)
    end

    test "member cannot delete" do
      {scope, org} = build_scope(:member)
      assert {:error, :unauthorized} = Policy.authorize(:api_delete, scope, org)
    end
  end

  defp build_scope(role) do
    user = Factory.insert(:user)
    org  = Factory.insert(:organization)
    mem  = Factory.insert(:membership, user: user, organization: org, role: role)
    scope = Scope.for_user(user) |> Scope.with_organization(org, mem)
    {scope, org}
  end
end
```

### Edge cases to cover

- Scope with `membership: nil` (user not in any org) — all actions must return `{:error, :unauthorized}`.
- Cross-org attempt: scope for org A, object is org B — `role/3` FK pin must reject.
- Unknown action atom — LetMe returns `{:error, :unauthorized}` for unregistered atoms, never crashes.
- `authorize_and_track` emits telemetry on denial — assert via `:telemetry.attach` in the test if verifying observability.

---

## Gotchas

### Action pairs must both exist

When adding a reversible lifecycle operation (e.g., `publish` / `unpublish`), always define both actions. Defining only `:api_publish` and forgetting `:api_unpublish` means unpublish will silently deny for everyone.

### Pass the organization struct, not the resource

All current `Checks.role/3` implementations expect an `%Organization{}` as the second argument. When authorizing an action on an `:api` or `:api_key`, pass `scope.organization` — the check cares about org membership, not the specific resource being acted upon. If you later need resource-level checks (e.g., "only the creator"), add a separate check function.

### FK pin match — never pass untrusted org

The `role/3` check compares `scope.organization.id` to the object's `id` (`obj_org_id`). If you build a synthetic `%Organization{id: some_id}` inline and pass it as the object, make sure `some_id` matches the scope's org or the check will deny. Always pass the org that was loaded from the session (`scope.organization`) as the object.

### Pre-check, not post-check

Policy is always called **before** the domain query. It does not re-verify ownership after fetching a record. Ownership checks (e.g., `key.organization_id == org.id`) are a separate concern handled in the context or LiveView after the policy gate passes. Both checks are needed: policy verifies the role has permission for the action type; the ownership check ensures the specific resource belongs to the current org.

### `authorize` never raises

LetMe's generated `authorize/3` always returns `:ok` or `{:error, :unauthorized}`. It never raises, even for unregistered action atoms. Do not rescue around it — pattern match the return value.

### Telemetry on denial is fire-and-forget

`Events.emit_policy_denied/1` uses `safe_execute`, which swallows errors. A failure in the telemetry pipeline will never cause the authorization response to change. The caller always receives `{:error, :unauthorized}` regardless of whether telemetry succeeds.
