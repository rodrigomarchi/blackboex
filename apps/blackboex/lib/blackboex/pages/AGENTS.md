# Pages Context

Free-form Markdown pages within projects for planning, documentation, and notes.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.Pages` | Facade — CRUD operations, `change_page/2` |
| `Blackboex.Pages.Page` | Schema — title, slug, content (text), status (draft/published), project_id, organization_id, user_id |
| `Blackboex.Pages.PageQueries` | Query builders — `list_for_project/1`, `by_project_and_slug/2`, `search/2` |

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
