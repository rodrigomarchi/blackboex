# AGENTS.md — Web Assets

Phoenix assets for `blackboex_web`: app/admin bootstraps, LiveView hooks,
browser adapters, and JavaScript tests.

## Rules

- Hooks are wiring only: DOM lookup, event listener registration, LiveView
  `pushEvent` / `handleEvent`, and lifecycle cleanup.
- Logic lives in `js/lib/**`: calculations, parsing, state machines, payload
  builders, storage adapters, CodeMirror/Tiptap/Drawflow helpers, and browser
  side-effect wrappers.
- Every new or changed hook must have a matching test in `test/hooks/**`.
- Every new or changed library module must have a matching test in `test/lib/**`.
- Every new or changed project-owned JavaScript file must keep a top-level
  JSDoc `@file` block, and exported functions/classes/helpers must keep JSDoc
  tags that pass the configured `eslint-plugin-jsdoc` rules.
- Use Vitest + jsdom. Do not add browser-only code that cannot be exercised with
  dependency injection or a small adapter wrapper.
- `vendor/**`, `node_modules/**`, compiled assets, and generated files are not
  refactoring targets.

## Structure

```text
assets/
├── js/
│   ├── app.js                 # user-facing LiveSocket bootstrap
│   ├── admin.js               # Backpex/admin LiveSocket bootstrap
│   ├── hooks/                 # LiveView hook wiring
│   └── lib/                   # testable logic and adapters
└── test/
    ├── helpers/hook_helper.js
    ├── hooks/
    └── lib/
```

## Commands

```bash
npm test --prefix apps/blackboex_web/assets
npm run lint --prefix apps/blackboex_web/assets
npm run format:check --prefix apps/blackboex_web/assets
make test.js
make lint.js
```

`make lint` includes JavaScript lint and format checks. `mix precommit` runs the
JavaScript test suite through an umbrella `cmd` step.

`app.js` is the single LiveSocket owner for the main web layout. It must import
and register every public `phx-hook` name used by that layout before calling
`new LiveSocket(...)`. Do not register hooks through `window.__hooks` or a
conditional feature bundle.

## Hook Pattern

Hooks should delegate meaningful decisions:

```javascript
import { classifyKey } from "../../lib/global/keyboard_shortcuts"

const MyHook = {
  mounted() {
    this.onKeyDown = (event) => {
      const action = classifyKey(event)
      if (!action) return
      event.preventDefault()
      this.pushEvent(action.event, action.payload)
    }
    window.addEventListener("keydown", this.onKeyDown)
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeyDown)
  },
}
```

Tests mount hooks through `test/helpers/hook_helper.js` and assert LiveView
events, DOM state, cleanup, timers, and storage behaviour.
