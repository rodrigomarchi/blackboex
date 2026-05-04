import { Editor } from "@tiptap/core";
import {
  createBubbleMenuEl,
  wireBubbleMenuButtons,
} from "../lib/tiptap/bubble_menu";
import {
  buildTiptapEditorProps,
  buildTiptapExtensions,
  buildTiptapOnUpdate,
} from "../lib/tiptap/editor_config";
import { tiptapDatasetOptions } from "../lib/tiptap/editor_options";
import { syncMarkdownContent } from "../lib/tiptap/markdown_sync";

// ── Editor Hook ─────────────────────────────────────────────

export function createTiptapEditorHook({
  EditorClass = Editor,
  buildExtensions = buildTiptapExtensions,
  buildEditorProps = buildTiptapEditorProps,
  buildOnUpdate = buildTiptapOnUpdate,
} = {}) {
  return {
    mounted() {
      const { content, readOnly, eventName, fieldName, placeholder } =
        tiptapDatasetOptions(this.el);

      const bubbleMenuEl = createBubbleMenuEl();
      this.el.appendChild(bubbleMenuEl);

      // Store pushEvent reference for keyboard shortcut save
      const pushEvent = eventName
        ? (payload) => this.pushEvent(eventName, payload)
        : null;

      this.editor = new EditorClass({
        element: this.el,
        extensions: buildExtensions({ bubbleMenuEl, placeholder }),
        content,
        editable: !readOnly,
        editorProps: buildEditorProps({
          getEditor: () => this.editor,
          fieldName,
          pushEvent,
          clearDebounce: () => clearTimeout(this._debounce),
        }),
        onUpdate: buildOnUpdate({ hook: this, eventName, fieldName }),
      });

      wireBubbleMenuButtons(bubbleMenuEl, this.editor);
    },

    updated() {
      // Skip if this update was triggered by our own pushEvent — avoids
      // infinite loop where setContent() recreates NodeViews (mermaid etc.)
      // which triggers onUpdate → pushEvent → updated() → setContent() again.
      if (this._pushingUpdate) {
        this._pushingUpdate = false;
        return;
      }
      const newValue = this.el.dataset.value;
      if (newValue !== undefined && this.editor) {
        if (newValue !== this.editor.storage.markdown.getMarkdown()) {
          // Mark the next onUpdate as caused by us, not by user typing.
          this._suppressNextOnUpdate = true;
          syncMarkdownContent(this.editor, newValue);
        }
      }
    },

    destroyed() {
      clearTimeout(this._debounce);
      if (this.editor) {
        this.editor.destroy();
        this.editor = null;
      }
    },
  };
}

const TiptapEditor = createTiptapEditorHook();

export default TiptapEditor;
