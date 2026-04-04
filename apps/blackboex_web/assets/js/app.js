// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/blackboex_web"
import { CodeEditorHook } from "live_monaco_editor/priv/static/live_monaco_editor.esm"
import { Hooks as BackpexHooks } from "backpex"
import topbar from "../vendor/topbar"

// Keyboard shortcuts hook for the API editor page
const KeyboardShortcuts = {
  mounted() {
    this.handleKeyDown = (e) => {
      const isMeta = e.metaKey || e.ctrlKey

      // Always handle Cmd+K (toggle command palette)
      if (isMeta && e.key === "k") {
        e.preventDefault()
        this.pushEvent("toggle_command_palette", {})
        return
      }

      // When command palette is open, only handle Escape
      const palette = document.querySelector("[data-command-palette]")
      if (palette) {
        if (e.key === "Escape") {
          e.preventDefault()
          this.pushEvent("toggle_command_palette", {})
        }
        return
      }

      if (isMeta && e.key === "s" && e.shiftKey) {
        e.preventDefault()
        this.pushEvent("save", {})
      } else if (isMeta && e.key === "s") {
        e.preventDefault()
        this.pushEvent("save", {})
      } else if (isMeta && e.key === "l") {
        e.preventDefault()
        this.pushEvent("toggle_chat", {})
      } else if (isMeta && e.key === "j") {
        e.preventDefault()
        this.pushEvent("toggle_bottom_panel", {})
      } else if (isMeta && e.key === "i" && !e.shiftKey) {
        e.preventDefault()
        this.pushEvent("toggle_config", {})
      } else if (isMeta && e.key === "Enter") {
        e.preventDefault()
        this.pushEvent("send_request", {})
      } else if (e.key === "Escape") {
        this.pushEvent("close_panels", {})
      }
    }

    window.addEventListener("keydown", this.handleKeyDown)
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeyDown)
  }
}

// Auto-focus hook for command palette input
const AutoFocus = {
  mounted() { this.el.focus() },
  updated() { this.el.focus() }
}

// Auto-scroll chat timeline to bottom on new content (including streaming tokens)
const ChatAutoScroll = {
  mounted() {
    this._userScrolledUp = false
    this._lastHeight = 0
    this.scrollToBottom()

    // MutationObserver catches DOM changes from LiveView patches
    this.observer = new MutationObserver(() => {
      if (!this._userScrolledUp) this.scrollToBottom()
    })
    this.observer.observe(this.el, { childList: true, subtree: true, characterData: true })

    // Polling fallback for streaming — MutationObserver can miss morphdom text patches
    this._poll = setInterval(() => {
      if (this.el.scrollHeight !== this._lastHeight) {
        this._lastHeight = this.el.scrollHeight
        if (!this._userScrolledUp) this.scrollToBottom()
      }
    }, 150)

    // Detect if user scrolled up manually — pause auto-scroll
    this.el.addEventListener("scroll", () => {
      const threshold = 80
      const atBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < threshold
      this._userScrolledUp = !atBottom
    })
  },
  updated() {
    if (!this._userScrolledUp) this.scrollToBottom()
  },
  destroyed() {
    if (this.observer) this.observer.disconnect()
    if (this._poll) clearInterval(this._poll)
  },
  scrollToBottom() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight
      // Also scroll inner streaming/code containers (they have max-h + overflow-y-auto)
      this.el.querySelectorAll(".overflow-y-auto").forEach(inner => {
        inner.scrollTop = inner.scrollHeight
      })
    })
  }
}

// Command palette keyboard navigation (arrows + Enter + Escape)
const CommandPaletteNav = {
  mounted() {
    this.el.focus()

    this.el.addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown") {
        e.preventDefault()
        this.pushEvent("command_palette_navigate", { direction: "down" })
      } else if (e.key === "ArrowUp") {
        e.preventDefault()
        this.pushEvent("command_palette_navigate", { direction: "up" })
      }
      // Enter is handled by phx-submit on the form
      // Escape is handled by the KeyboardShortcuts hook
    })
  },

  updated() {
    this.el.focus()

    // Scroll the selected item into view
    const list = document.getElementById("command-palette-list")
    if (list) {
      const selected = list.querySelector("[class*='bg-base-200']")
      if (selected) {
        selected.scrollIntoView({ block: "nearest" })
      }
    }
  }
}

// Monaco Diff Editor hook — fullscreen side-by-side diff viewer
const MonacoDiffEditor = {
  mounted() {
    this.diffEditor = null
    this.originalModel = null
    this.modifiedModel = null

    this.handleEvent("open_diff", ({ original, modified, language }) => {
      this._createDiffEditor(original, modified, language || "elixir")
    })
  },

  updated() {
    if (this.diffEditor) this.diffEditor.layout()
  },

  async _createDiffEditor(original, modified, language) {
    this._dispose()

    const monaco = await this._waitForMonaco()

    this.originalModel = monaco.editor.createModel(original, language)
    this.modifiedModel = monaco.editor.createModel(modified, language)

    const theme = document.documentElement.getAttribute("data-theme")
    const isLight = theme === "light" ||
      (!theme && window.matchMedia("(prefers-color-scheme: light)").matches)

    this.diffEditor = monaco.editor.createDiffEditor(this.el, {
      automaticLayout: true,
      readOnly: true,
      originalEditable: false,
      renderSideBySide: true,
      theme: isLight ? "vs" : "default",
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
      fontSize: 13,
      lineNumbers: "on",
      enableSplitViewResizing: true,
      ignoreTrimWhitespace: true,
      renderIndicators: true,
    })

    this.diffEditor.setModel({
      original: this.originalModel,
      modified: this.modifiedModel,
    })
  },

  _waitForMonaco() {
    return new Promise((resolve, reject) => {
      if (window.monaco) return resolve(window.monaco)
      let attempts = 0
      const interval = setInterval(() => {
        attempts++
        if (window.monaco) { clearInterval(interval); resolve(window.monaco) }
        else if (attempts > 50) { clearInterval(interval); reject(new Error("Monaco not available")) }
      }, 100)
    })
  },

  _dispose() {
    if (this.originalModel) { this.originalModel.dispose(); this.originalModel = null }
    if (this.modifiedModel) { this.modifiedModel.dispose(); this.modifiedModel = null }
    if (this.diffEditor) { this.diffEditor.dispose(); this.diffEditor = null }
  },

  destroyed() { this._dispose() },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, CodeEditorHook, MonacoDiffEditor, KeyboardShortcuts, AutoFocus, ChatAutoScroll, CommandPaletteNav, ...BackpexHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// Copy to clipboard handler for code snippets
window.addEventListener("phx:copy_to_clipboard", (event) => {
  if (navigator.clipboard && event.detail.text) {
    navigator.clipboard.writeText(event.detail.text)
  }
})

// Force Monaco editor to recalculate layout when panels toggle.
// Monaco doesn't automatically detect container size changes.
const relayoutMonaco = () => {
  // Monaco stores editor instances on the window.monaco global
  if (window.monaco && window.monaco.editor) {
    const editors = window.monaco.editor.getEditors()
    if (editors) {
      editors.forEach(e => e.layout())
    }
  }
}

// Use MutationObserver on the editor root to detect panel open/close
const setupMonacoRelayout = () => {
  const root = document.getElementById("editor-root")
  if (!root) return

  const observer = new MutationObserver(() => {
    // Debounce to avoid rapid relayout calls
    clearTimeout(window._monacoRelayoutTimer)
    window._monacoRelayoutTimer = setTimeout(relayoutMonaco, 50)
  })

  observer.observe(root, { childList: true, subtree: true })
}

// Sync Monaco editor theme with app theme (light/dark)
const syncMonacoTheme = () => {
  if (!window.monaco || !window.monaco.editor) return

  const theme = document.documentElement.getAttribute("data-theme")
  const isLight = theme === "light" ||
    (!theme && window.matchMedia("(prefers-color-scheme: light)").matches)

  // "default" is the dark theme defined by LiveMonacoEditor, "vs" is Monaco's built-in light theme
  window.monaco.editor.setTheme(isLight ? "vs" : "default")
}

// Relayout Monaco after panels toggle or tab switch
const setupMonacoResizeObserver = () => {
  const container = document.getElementById("monaco-container")
  if (!container || container._resizeObserverAttached) return

  const observer = new ResizeObserver(() => {
    clearTimeout(window._monacoResizeTimer)
    window._monacoResizeTimer = setTimeout(relayoutMonaco, 30)
  })
  observer.observe(container)
  container._resizeObserverAttached = true
}

// Setup after LiveView connects
window.addEventListener("phx:page-loading-stop", () => {
  setTimeout(setupMonacoRelayout, 100)
  setTimeout(setupMonacoResizeObserver, 150)
  setTimeout(syncMonacoTheme, 200)
})

// Re-sync when theme changes
window.addEventListener("phx:set-theme", () => setTimeout(syncMonacoTheme, 50))
window.addEventListener("storage", (e) => {
  if (e.key === "phx:theme") setTimeout(syncMonacoTheme, 50)
})

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

