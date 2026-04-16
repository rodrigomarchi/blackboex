// Feature bundle: CodeMirror code editor
// Loaded on pages that use the CodeEditor hook (playground, API editor)
import CodeEditor from "./hooks/code_editor"
import PlaygroundEditor from "./hooks/playground_editor"
import ResizablePanels from "./hooks/resizable_panels"

window.__hooks = window.__hooks || {}
window.__hooks.CodeEditor = CodeEditor
window.__hooks.PlaygroundEditor = PlaygroundEditor
window.__hooks.ResizablePanels = ResizablePanels
