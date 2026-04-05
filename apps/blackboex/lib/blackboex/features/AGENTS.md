# AGENTS.md — Features Context

Feature flag system powered by FunWithFlags ~> 1.13. Flags gate functionality by global state, individual user identity, or subscription plan group. The domain app (`blackboex`) owns all flag protocol implementations; no Phoenix dependency required.

## Files

```
apps/blackboex/lib/blackboex/features/
  actor_impl.ex   — FunWithFlags.Actor protocol for Blackboex.Accounts.User
  group_impl.ex   — FunWithFlags.Group protocol for Blackboex.Accounts.User
```

---

## ActorImpl

**File:** `actor_impl.ex`

Implements `FunWithFlags.Actor` for `Blackboex.Accounts.User`. Actor ID: `"user:<uuid>"`.

Actor overrides take precedence over group membership. If a flag is globally disabled but enabled `for_actor: user`, the check returns `true` for that user.

---

## GroupImpl

**File:** `group_impl.ex`

Implements `FunWithFlags.Group` for `Blackboex.Accounts.User`. Plan resolution delegates to `Blackboex.Organizations.get_user_primary_plan/1`, which queries the user's first organization (ordered by `memberships.inserted_at asc`) and returns its plan atom (`:free`, `:pro`, `:enterprise`). Returns `:free` when the user has no organization.

### Defined groups

| Group atom    | Matches plans          | Notes                          |
|---------------|------------------------|--------------------------------|
| `:pro`        | `:pro`, `:enterprise`  | Enterprise users are also pro  |
| `:enterprise` | `:enterprise` only     | Strict enterprise check        |

Any group name not matched by the `in?/2` clauses returns `false` — new groups require a new clause in `group_impl.ex`.

---

## How to Add New Flags

1. Use `snake_case` atoms — canonical form. Stored as strings in DB, but always pass atoms at call sites.
2. Choose targeting: global on/off, `for_actor: user`, or `for_group: :pro/:enterprise`. New groups require a new clause in `group_impl.ex`.
3. Call `FunWithFlags.enabled?(:flag)` or `FunWithFlags.enabled?(:flag, for: user)` at the feature boundary. No registration step needed — the flag is created on first use.
4. Compute flag values in `mount/3` or `handle_params/3` and store as socket assigns. Never call `FunWithFlags.enabled?/2` inside `render/1` or templates.
5. Document the flag in the Existing Flags table below.

---

## Existing Flags

| Flag atom        | Strategy | Description                                                                 |
|------------------|----------|-----------------------------------------------------------------------------|
| `:agent_pipeline` | Global / user | Controls whether the AI agent code generation pipeline is active. Referenced in `scripts/test_agent_pipeline.exs`. The `Agent.KickoffWorker` and `Agent.Session` are the primary consumers. |

When a new flag is added, append a row to this table.

---

## Config

- **Dev/prod** (`config/config.exs`): Ecto adapter persists flags to `fun_with_flags_toggles` table; cache-bust notifications over `Blackboex.PubSub`.
- **Test** (`config/test.exs`): ETS cache disabled (`cache: [enabled: false]`) — flag changes take effect immediately without staleness.

---

## Testing

ETS cache is disabled in tests; `enable/2` and `disable/2` take effect immediately. Always clean up in `on_exit`:

```elixir
setup do
  FunWithFlags.enable(:agent_pipeline)
  on_exit(fn -> FunWithFlags.clear(:agent_pipeline) end)
  :ok
end
```

Prefer `clear/1` over `disable/1` in `on_exit` — it removes all gates rather than leaving an explicit `false` gate that could mask missing `enable` calls in other tests.

For plan-gated flags, insert an organization with the target plan, then call `FunWithFlags.enable(:flag, for_group: :pro)`.

---

## Gotchas

**Cache is enabled in dev/prod, disabled in test.** Flag changes propagate via PubSub cache-bust; brief stale window is expected. Do not disable the cache in non-test environments.

**`get_user_primary_plan/1` issues a DB query.** `GroupImpl.in?/2` calls it on every group-scoped `enabled?/2` call. In hot paths, preload the plan or cache the result in a socket assign.

**Clearing vs disabling.** `disable/1` adds a boolean `false` gate; `clear/1` removes all gates. In tests, prefer `clear/1` in `on_exit`.

**Migration required before first deploy.** The `fun_with_flags_toggles` table must exist. Migration: `apps/blackboex/priv/repo/migrations/20260320114237_create_fun_with_flags_tables.exs`. Run `make db.migrate` first.
