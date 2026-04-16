import { EditorState } from "@codemirror/state"
import { EditorView, keymap } from "@codemirror/view"
import { autocompletion } from "@codemirror/autocomplete"
import { buildExtensions } from "../lib/codemirror_setup"
import { elixirCompletionSource } from "../lib/elixir_completion"

const PlaygroundEditor = {
  mounted() {
    const initialValue = this.el.dataset.value || ""

    const extensions = buildExtensions({
      language: "elixir",
      readOnly: false,
      onBlur: null,
      minimal: false,
    })

    // Keyboard shortcuts for playground actions
    const playgroundKeymap = keymap.of([
      {
        key: "Mod-Enter",
        run: () => {
          this.pushEvent("run", {})
          return true
        },
      },
      {
        key: "Mod-s",
        run: () => {
          this.pushEvent("save_code", {})
          return true
        },
      },
      {
        key: "Mod-Shift-f",
        run: () => {
          this.pushEvent("format_code", {})
          return true
        },
      },
    ])

    // Debounced code sync on every change
    let debounceTimer = null
    const updateListener = EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        clearTimeout(debounceTimer)
        debounceTimer = setTimeout(() => {
          const value = update.state.doc.toString()
          this.pushEvent("update_code", { value })
        }, 300)
      }
    })

    // Server-driven code completion
    const completionExt = autocompletion({
      override: [elixirCompletionSource(this)],
      activateOnTyping: true,
    })

    const state = EditorState.create({
      doc: initialValue,
      extensions: [...extensions, playgroundKeymap, updateListener, completionExt],
    })

    this.view = new EditorView({ state, parent: this.el })

    // Handle server-pushed formatted code
    this.handleEvent("formatted_code", ({ code }) => {
      if (this.view) {
        this.view.dispatch({
          changes: {
            from: 0,
            to: this.view.state.doc.length,
            insert: code,
          },
        })
      }
    })

    // Handle server-pushed completion results (wired in Phase 3)
    this._completionResolve = null
    this.handleEvent("completion_results", ({ items }) => {
      if (this._completionResolve) {
        this._completionResolve(items)
        this._completionResolve = null
      }
    })
  },

  updated() {
    const newValue = this.el.dataset.value
    if (newValue !== undefined && this.view) {
      const currentValue = this.view.state.doc.toString()
      if (newValue !== currentValue) {
        this.view.dispatch({
          changes: { from: 0, to: this.view.state.doc.length, insert: newValue },
        })
      }
    }
  },

  destroyed() {
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
  },
}

export default PlaygroundEditor
