import { EditorState } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import { buildExtensions } from "../lib/codemirror_setup"

const CodeEditor = {
  mounted() {
    const language = this.el.dataset.language || "text"
    const readOnly = this.el.dataset.readonly === "true"
    const eventName = this.el.dataset.event
    const fieldName = this.el.dataset.field
    const initialValue = this.el.dataset.value || ""

    const onBlur = (!readOnly && eventName)
      ? (_event, view) => {
          const value = view.state.doc.toString()
          const payload = fieldName ? { field: fieldName, value } : { value }
          this.pushEvent(eventName, payload)
        }
      : null

    const extensions = buildExtensions({ language, readOnly, onBlur })

    const state = EditorState.create({
      doc: initialValue,
      extensions,
    })

    this.view = new EditorView({ state, parent: this.el })
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

export default CodeEditor
