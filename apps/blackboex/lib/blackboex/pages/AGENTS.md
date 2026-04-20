# Pages Context

Free-form Markdown pages within projects for planning, documentation, and notes.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.Pages` | Facade — CRUD operations, `change_page/2`, `list_root_pages_for_project/2` |
| `Blackboex.Pages.Page` | Schema — title, slug, content (text), status (draft/published), project_id, organization_id, user_id |
| `Blackboex.Pages.PageQueries` | Query builders — `list_for_project/1`, `by_project_and_slug/2`, `search/2`, `root_pages_for_project/2` |

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `list_root_pages_for_project/2` | `(project_id, opts \\ [])` | `[Page.t()]` | Root pages (parent_id IS NULL) for a project, ordered by title ASC. Accepts `:limit` opt (default 100). |
| `list_pages/1` | `(project_id)` | `[Page.t()]` | All pages for a project, ordered by updated_at DESC |
| `list_pages/2` | `(project_id, opts)` | `[Page.t()]` | All pages with optional `search:` filter |
| `list_page_tree/1` | `(project_id)` | `[map()]` | Nested tree: `%{page: Page.t(), children: [...]}` |
| `create_page/1` | `(attrs)` | `{:ok, Page.t()} \| {:error, ...}` | Creates a page; validates project belongs to org |
| `get_page/2` | `(project_id, page_id)` | `Page.t() \| nil` | Fetch by project + id |
| `get_for_org/2` | `(org_id, page_id)` | `Page.t() \| nil` | Org-scoped fetch by id; returns nil when not found or cross-org |
| `get_page_by_slug/2` | `(project_id, slug)` | `Page.t() \| nil` | Fetch by project + slug |
| `update_page/2` | `(page, attrs)` | `{:ok, Page.t()} \| {:error, ...}` | Update title, content, status; slug is immutable |
| `delete_page/1` | `(page)` | `{:ok, Page.t()} \| {:error, ...}` | Delete a page (children become root) |
| `move_page/3` | `(page, new_parent_id, position)` | `{:ok, Page.t()} \| {:error, atom()}` | Move page in tree; validates depth ≤5, no circular refs |
| `change_page/2` | `(page, attrs \\ %{})` | `Ecto.Changeset.t()` | Build changeset for form use |

## Key Patterns

- **Slug**: Auto-generated from title with nanoid hash, immutable after creation (`update_changeset` excludes slug)
- **Content validation**: Max 1MB (1,048,576 chars)
- **LIKE search**: Sanitizes `%`, `_`, `\` wildcards before interpolation
- **Denormalized `organization_id`**: Follows project-scoped entity convention (same as Api, Flow)

## Policy Rules

Defined in `Blackboex.Policy` under `object :page`:
- `:create` / `:update` — owner, admin, member, project editor
- `:read` — owner, admin, member, project viewer
- `:delete` — owner, admin, project admin

## Fixtures

`Blackboex.PagesFixtures.page_fixture/1` — auto-imported via DataCase/ConnCase.
Named setup: `create_page/1` (requires `:user` + `:org` in context).
