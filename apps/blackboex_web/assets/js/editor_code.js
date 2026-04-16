// Feature bundle: CodeMirror code editor
// Loaded on pages that use the CodeEditor hook (playground, API editor)
import CodeEditor from "./hooks/code_editor"
import PlaygroundEditor from "./hooks/playground_editor"

window.__hooks = window.__hooks || {}
window.__hooks.CodeEditor = CodeEditor
window.__hooks.PlaygroundEditor = PlaygroundEditor
