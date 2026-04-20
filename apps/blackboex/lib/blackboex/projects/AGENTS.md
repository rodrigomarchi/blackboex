# Projects — Groups resources within an organization

## Overview

`Blackboex.Projects` organizes APIs, Flows, Pages, and other resources into named workspaces within an Organization. Users can belong to specific projects with granular roles (`admin`, `editor`, `viewer`). Org owners and admins have implicit access to all projects; other users only see projects they are explicitly added to.

## Modules

### `Blackboex.Projects` (`lib/blackboex/projects.ex`)
Public facade. All callers (LiveViews, workers, policies) go through this module.

### `Blackboex.Projects.Project` (`lib/blackboex/projects/project.ex`)
Ecto schema for a project.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `binary_id` | UUID primary key |
| `name` | `string` | Human-readable project name |
| `slug` | `string` | URL-safe identifier, auto-generated from name + 6-char Nanoid suffix. Immutable after creation |
| `description` | `string` | Optional description |
| `member_count` | `integer` | Virtual field, populated by `ProjectQueries.with_member_count/1` |
| `organization_id` | `binary_id` FK | Owning organization |

Unique constraint: `(organization_id, slug)` — slugs are unique per org.

**Slug generation:** `name` is lowercased, non-alphanumeric chars stripped, spaces replaced with hyphens, then a 6-char random suffix is appended (e.g. `"My API"` → `"my-api-x3k9mz"`). Slug is immutable — `update_changeset/2` does not accept slug changes.

### `Blackboex.Projects.ProjectMembership` (`lib/blackboex/projects/project_membership.ex`)
Join table between projects and users with a role.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `binary_id` | UUID primary key |
| `role` | `Ecto.Enum` | `:admin`, `:editor`, or `:viewer` |
| `project_id` | `binary_id` FK | Project |
| `user_id` | `integer` FK | User (integer FK matching `accounts` users table) |

Unique constraint: `(project_id, user_id)` — a user has at most one role per project.

### `Blackboex.Projects.ProjectQueries` (`lib/blackboex/projects/project_queries.ex`)
Query builders only — no `Repo` calls, no side effects.

| Function | Description |
|----------|-------------|
| `for_organization/1` | All projects in an org |
| `by_org_and_slug/2` | Single project by org + slug |
| `by_org_and_id/2` | Single project by org + id |
| `for_user/2` | Projects accessible to a user: all projects if user is org owner/admin, otherwise only projects with a `ProjectMembership` |
| `with_member_count/1` | Composable — adds virtual `member_count` via LEFT JOIN + GROUP BY |
| `list_with_counts/1` | Returns `Ecto.Query.t()` selecting projects + 4 correlated subquery counts (pages, apis, flows, playgrounds). Called by `Projects.list_projects_with_counts/1` via `Repo.all()`. |

## Public API

### Project CRUD

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `list_projects_with_counts/1` | `(Organization.t())` | `[%{project: Project.t(), pages_count: integer(), apis_count: integer(), flows_count: integer(), playgrounds_count: integer()}]` | All projects for an org with 4 resource counts in ONE SQL query, ordered by name ASC |
| `create_project/3` | `(org, user, attrs)` | `{:ok, %{project: Project.t(), membership: ProjectMembership.t()}}` | Creates project + adds creator as `:admin` in a transaction |
| `create_default_project/2` | `(org, user)` | same | Creates a `"Default"` project for new organizations |
| `list_projects/1` | `(organization_id)` | `[Project.t()]` | All projects in an org |
| `list_user_projects/2` | `(organization_id, user_id)` | `[Project.t()]` | Projects visible to the user (respects access rules) |
| `count_projects_for_org/1` | `(organization_id)` | `non_neg_integer()` | Count of projects in an org |
| `get_project/2` | `(organization_id, project_id)` | `Project.t() \| nil` | Org-scoped fetch by ID |
| `get_project_by_slug/2` | `(organization_id, slug)` | `Project.t() \| nil` | Org-scoped fetch by slug |
| `get_default_project/1` | `(organization_id)` | `Project.t() \| nil` | Oldest project for an org (used as fallback) |
| `update_project/2` | `(project, attrs)` | `{:ok, Project.t()}` | Updates `name` and `description` only; slug is immutable |
| `delete_project/1` | `(project)` | `{:ok, Project.t()}` | Hard deletes the project |

### Membership Management

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `add_project_member/3` | `(project, user, role)` | `{:ok, ProjectMembership.t()}` | Adds a user to a project with a role |
| `remove_project_member/1` | `(membership)` | `{:ok, ProjectMembership.t()}` | Removes a member from a project |
| `update_project_member_role/2` | `(membership, role)` | `{:ok, ProjectMembership.t()}` | Changes a member's role |
| `get_project_membership/2` | `(project, user)` | `ProjectMembership.t() \| nil` | Looks up a specific membership |
| `list_project_members/1` | `(project_id)` | `[ProjectMembership.t()]` | All members with user preloaded |
| `list_eligible_members/2` | `(org, project)` | `[Membership.t()]` | Org members not yet in the project (for add-member UI) |
| `user_has_project_access?/4` | `(org, membership, project, user)` | `boolean()` | True if user is org owner/admin OR has a ProjectMembership |

## Access Rules

- Org `owner` and `admin` roles have implicit access to **all** projects in their org
- All other org members can only see and access projects where they have an explicit `ProjectMembership`
- `ProjectQueries.for_user/2` encodes this logic at the query level — always use it for user-facing project lists
- `user_has_project_access?/4` is the runtime check — call it before allowing project-scoped operations

## Invariants

- `create_project/3` always uses an `Ecto.Multi` transaction — project creation and creator membership are atomic
- Slug is **immutable** after creation — `update_changeset/2` only accepts `name` and `description`
- `get_project/2` and `get_project_by_slug/2` are org-scoped — never use `Repo.get/2` directly from web/worker code
- Every new project gets the creating user as `:admin` — there is always at least one admin member
