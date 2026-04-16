// Feature bundle: CodeMirror code editor
// Loaded on pages that use the CodeEditor hook (playground, API editor)
import CodeEditor from "./hooks/code_editor"

window.__hooks = window.__hooks || {}
window.__hooks.CodeEditor = CodeEditor
