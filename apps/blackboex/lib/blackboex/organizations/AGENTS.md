# AGENTS.md — Organizations Context

Multi-tenancy layer. Facade: `Blackboex.Organizations` (`organizations.ex`).

## Query Module

`OrganizationQueries` — all `Ecto.Query` composition for organizations and memberships. Sub-modules call `OrganizationQueries`, not inline queries.

## Schemas

| Schema | Table | Notes |
|--------|-------|-------|
| `Organization` | `organizations` | `id` uuid, `slug` unique, `plan` default "free" |
| `Membership` | `memberships` | `user_id` integer FK, `org_id` uuid FK, unique `(user_id, org_id)` |
| `Invitation` | `org_invitations` | `org_id` uuid FK, email + role, hashed token, `expires_at`, `accepted_at` |

**Mixed FK types:** `user_id` is `type: :id` (integer); `organization_id` is `:binary_id`. Preserve in any new schema referencing both.

## Public API

```elixir
create_organization(User.t(), map()) :: {:ok, %{organization, membership}} | {:error, ...}
list_user_organizations(User.t()) :: [Organization.t()]
get_organization!(uuid) :: Organization.t()
get_organization(uuid) :: Organization.t() | nil
add_member(Organization.t(), User.t(), atom()) :: {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
get_user_membership(Organization.t(), User.t()) :: Membership.t() | nil
invite_member(Organization.t(), email :: String.t(), role :: atom()) :: {:ok, Invitation.t()} | {:error, ...}
accept_invitation(token :: String.t(), attrs :: map()) :: {:ok, %{user, membership}} | {:error, ...}
```

## Roles

| Role | Permissions |
|------|-------------|
| `:owner` | Full control — members, delete org |
| `:admin` | Create/update/delete APIs, manage members and keys |
| `:member` | Read + create/update APIs. No delete, no member management |

## Multi-tenancy Rules

1. **No cross-org access.** Every resource fetch must include `organization_id`. Bare ID = IDOR.
2. **Membership is the gate.** `Accounts.Scope` carries `user + organization`. `SetOrganization` hook sets scope from session.
3. **Slug is the public URL key.** `/p/:org_slug/:api_slug` — treat as stable once set.
4. **`create_organization/2` is atomic.** `Ecto.Multi` — org + membership. Failure rolls back both.

## Gotchas

1. **Slug collisions at registration** — personal org uses `email_prefix + random_6char_suffix`. Multi fails at `:organization` on collision.
2. **`add_member/3` returns `{:error, changeset}` for duplicate** — unique index `(user_id, org_id)`.
3. **`list_user_organizations/1` does not preload memberships** — call `get_user_membership/2` separately.
