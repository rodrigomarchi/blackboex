# Blackboex

**Describe an API in natural language. Blackboex generates, compiles, tests, and publishes it as a live HTTP endpoint.**

Blackboex is an open-source platform built with Elixir/Phoenix where users create AI-powered APIs through a visual editor or natural language descriptions. An AI agent handles code generation, validation, and deployment — no boilerplate required.

## Features

- **Natural language → live API** — describe what your endpoint should do; the AI agent generates and deploys it
- **Visual flow editor** — build multi-step workflows with a drag-and-drop interface (Drawflow-based)
- **Playgrounds** — interactive sandbox to test and iterate on AI-generated code in real time
- **Pages** — markdown-based content pages with an AI-assisted editor
- **Multi-tenant** — organizations, projects, and role-based access control out of the box
- **Observability** — OpenTelemetry tracing, Prometheus metrics, structured JSON logging
- **Admin panel** — full Backpex-powered admin interface

## Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.19+ / OTP 28+ |
| Web | Phoenix 1.8+ / LiveView 1.1+ |
| Database | PostgreSQL 16+ via Ecto |
| AI | LangChain + Anthropic Claude (per-project keys) |
| Jobs | Oban |
| Frontend | Tailwind CSS + esbuild (no npm for builds) |
| Components | SaladUI + Backpex |
| HTTP server | Bandit |

## Prerequisites

- Elixir 1.19+ and OTP 28+ ([install via asdf](https://asdf-vm.com) or [mise](https://mise.jdx.dev))
- PostgreSQL 16+
- Docker (for the local dev stack via `make docker.up`)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/rodrigomarchi/blackboex.git
cd blackboex

# 2. Copy and fill environment variables
cp .env.example .env
# Edit .env — at minimum set SECRET_KEY_BASE, CLOAK_KEY, MAILER_API_KEY

# 3. First-time setup (Docker + deps + DB)
make setup

# 4. Start the dev server
make server
# → http://localhost:4000
```

## Environment Variables

All configuration is via environment variables. See [`.env.example`](.env.example) for the full list with descriptions.

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes | Phoenix secret (`mix phx.gen.secret`) |
| `PHX_HOST` | Yes | Public hostname |
| `CLOAK_KEY` | Yes | Encryption key (`mix cloak.gen.key AES.GCM`) |
| `MAILER_API_KEY` | Yes | Email API key (Resend / Mailgun) |
| `PORT` | No | HTTP port (default: `4000`) |
| `PLAYGROUND_BASE_URL` | No | Sandbox base URL |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | OTLP endpoint (default: `http://localhost:4318`) |

## Common Commands

```bash
make server          # Dev server (localhost:4000)
make test            # Full test suite
make lint            # format + credo + dialyzer
make precommit       # compile + format + test

make db.migrate      # Run pending migrations
make db.reset        # Drop + create + migrate + seed
make routes          # List all routes
make iex             # Interactive console

make docker.up       # Start PostgreSQL + observability stack
make docker.down     # Stop Docker services
```

## Architecture

Blackboex is an **Elixir umbrella application** with strict domain/web separation:

```
apps/
├── blackboex/        # Domain app — zero Phoenix deps
│   ├── accounts/     # Auth, users, sessions
│   ├── apis/         # Core entity: AI-generated APIs
│   ├── flows/        # Visual workflow engine
│   ├── agent/        # AI pipeline orchestration
│   ├── organizations/ # Multi-tenancy
│   ├── projects/     # Project grouping within orgs
│   ├── playgrounds/  # Interactive code sandboxes
│   └── pages/        # Markdown content pages
└── blackboex_web/    # Web app — Phoenix, LiveView, admin
    ├── live/         # LiveView pages
    ├── components/   # SaladUI + shared components
    └── admin/        # Backpex admin panel
```

Each domain context follows a **facade + Queries + sub-context** pattern. See [`AGENTS.md`](AGENTS.md) for the full context map and [`docs/architecture.md`](docs/architecture.md) for data flows and invariants.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

[MIT](LICENSE) — Copyright (c) 2026 Rodrigo Marchi
