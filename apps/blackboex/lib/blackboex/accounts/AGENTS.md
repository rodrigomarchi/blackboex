# AGENTS.md — Accounts Context

User identity, authentication, session lifecycle, and the `Scope` struct. Facade: `Blackboex.Accounts` (`accounts.ex`).

## Query Module

`UserQueries` — all `Ecto.Query` composition for user lookups. The facade and sub-modules call `UserQueries`, not inline queries.

## Modules

| File | Purpose |
|------|---------|
| `scope.ex` | `Scope` struct — central carrier for `{user, organization, membership}` |
| `user.ex` | User schema and changesets |
| `user_token.ex` | Token schema, generation, verification |
| `user_notifier.ex` | Swoosh email delivery |
| `user_queries.ex` | Query builders for user lookups |
| `../accounts.ex` | Public facade — only entry point for callers |

## Scope Struct

`%Scope{user, organization, membership}` — the single most important struct. Every domain function that touches tenant data receives a Scope.

```elixir
Scope.for_user(user)                          # step 1: after session lookup
Scope.with_organization(scope, org, membership) # step 2: after SetOrganization hook
```

Flow: `fetch_current_scope_for_user` plug → `SetOrganization` hook → `socket.assigns.current_scope`

## Key Public Functions

```elixir
register_user(attrs) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()} | {:error, :registration_failed}
# Atomic Multi: insert User → create org → create owner Membership

get_user_by_session_token(token) :: {User.t(), DateTime.t()} | nil
generate_user_session_token(user) :: binary()
delete_user_session_token(token) :: :ok

login_user_by_magic_link(token) :: {:ok, {User.t(), [UserToken.t()]}} | {:error, :not_found}
get_user_by_magic_link_token(token) :: User.t() | nil
deliver_login_instructions(user, url_fun) :: {:ok, Swoosh.Email.t()} | {:error, term()}

sudo_mode?(user, minutes \\ -20) :: boolean()
```

## Token Contexts

| Context | Storage | Expiry |
|---------|---------|--------|
| `"session"` | Raw bytes | 14 days |
| `"login"` | SHA-256 hash | 15 minutes |
| `"change:#{old_email}"` | SHA-256 hash | 7 days |

## User Preferences

The `users` table has a JSONB column `preferences` (default `%{}`). Access is managed entirely through two facade functions — never write to this column directly from callers.

### Whitelist

```elixir
@preferences_allowed_roots ~w(sidebar_tree)
```

Only paths whose first segment is in this list are accepted. Add new roots here as features require them. This is the single source of truth — do not duplicate the list.

### Functions

```elixir
@spec update_user_preference(User.t(), [String.t()], term()) ::
        {:ok, User.t()} | {:error, Ecto.Changeset.t() | :forbidden}
# path must be non-empty and hd(path) must be in @preferences_allowed_roots.
# Missing intermediate keys are created automatically (Access.key/2 with %{}).
# Uses User.preferences_changeset/2 — only :preferences is ever touched.

@spec get_user_preference(User.t(), [String.t()], default) :: term() | default when default: var
# Traverses user.preferences with string keys. Returns default on any missing segment.
# Never raises KeyError. Path segments are strings (JSONB keys are NOT atoms).
```

### Gotchas

- **String keys only** — JSONB round-trips keys as strings. Never use atom keys in preferences.
- **`update_user_preference` with `[]` path returns `{:error, :forbidden}`** — replacing the whole map is not allowed.
- **`preferences_changeset/2` is isolated** — no other changeset (`email_changeset`, `password_changeset`, etc.) casts `:preferences`. Callers cannot sneak preferences through registration.

## Gotchas

1. **Never compare session tokens with `==`** — use `Plug.Crypto.secure_compare/2`.
2. **`authenticated_at` is a virtual field** — populated from token at session load. Not in DB.
3. **Magic link includes `sent_to == user.email` check** — stale links invalidated on email change.
4. **`get_user!/1` is not for external input** — raises on not found. Use `get_user/1` for user-facing lookups.
5. **Bcrypt truncates at 72 bytes** — `password_changeset` validates `max: 72, count: :bytes`.
6. **No token pruning job** — expired tokens accumulate until password change or magic-link confirmation.
