// Feature bundle: Tiptap WYSIWYG editor
// Loaded only on pages that use the TiptapEditor hook (page editor)
import TiptapEditor from "./hooks/tiptap_editor"

window.__hooks = window.__hooks || {}
window.__hooks.TiptapEditor = TiptapEditor
