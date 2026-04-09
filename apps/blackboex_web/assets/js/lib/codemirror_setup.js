import { keymap, EditorView } from "@codemirror/view"
import { defaultKeymap, indentWithTab } from "@codemirror/commands"
import { closeBrackets } from "@codemirror/autocomplete"
import { bracketMatching, indentOnInput, StreamLanguage } from "@codemirror/language"
import { json, jsonParseLinter } from "@codemirror/lang-json"
import { linter } from "@codemirror/lint"
import { ruby } from "@codemirror/legacy-modes/mode/ruby"
import { EditorState } from "@codemirror/state"
import { lineNumbers, highlightActiveLineGutter, highlightActiveLine } from "@codemirror/view"
import { blackboexEditorTheme } from "./codemirror_theme"

export function buildExtensions({ language, readOnly, onBlur }) {
  const extensions = [
    lineNumbers(),
    highlightActiveLineGutter(),
    highlightActiveLine(),
    bracketMatching(),
    indentOnInput(),
    closeBrackets(),
    keymap.of([...defaultKeymap, indentWithTab]),
    blackboexEditorTheme,
  ]

  if (language === "elixir") {
    extensions.push(StreamLanguage.define(ruby))
  } else if (language === "json") {
    extensions.push(json())
    extensions.push(linter(jsonParseLinter()))
  }

  if (readOnly) {
    extensions.push(EditorState.readOnly.of(true))
    extensions.push(EditorView.editable.of(false))
  }

  if (onBlur) {
    extensions.push(EditorView.domEventHandlers({ blur: onBlur }))
  }

  return extensions
}
