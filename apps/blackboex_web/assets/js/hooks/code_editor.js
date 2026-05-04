import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { buildExtensions } from "../lib/codemirror_setup";
import {
  buildBlurHandler,
  buildCodeEditorOptions,
  syncCodeMirrorDocument,
} from "../lib/editor/code_editor";

const CodeEditor = {
  mounted() {
    const options = buildCodeEditorOptions(this.el);
    const onBlur = buildBlurHandler(this, options);

    const extensions = buildExtensions({ ...options, onBlur });

    const state = EditorState.create({
      doc: options.initialValue,
      extensions,
    });

    this.view = new EditorView({ state, parent: this.el });
  },

  updated() {
    syncCodeMirrorDocument(this.view, this.el.dataset.value);
  },

  destroyed() {
    if (this.view) {
      this.view.destroy();
      this.view = null;
    }
  },
};

export default CodeEditor;
