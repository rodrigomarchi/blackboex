// Feature bundle: Drawflow visual editor + CodeMirror for execution view
// Loaded only on the flow editor page
import DrawflowEditor from "./hooks/drawflow_editor"
import CodeEditor from "./hooks/code_editor"

window.__hooks = window.__hooks || {}
window.__hooks.DrawflowEditor = DrawflowEditor
window.__hooks.CodeEditor = CodeEditor
