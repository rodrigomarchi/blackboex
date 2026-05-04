/**
 * @file LiveView hook that mounts CodeMirror for generic code editor fields.
 */
/**
 * @typedef {object} LiveViewHook
 * @property {HTMLElement} el
 * @property {(event: string, payload: object, callback?: Function) => void} pushEvent
 * @property {(event: string, callback: Function) => void} handleEvent
 */
import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { buildExtensions } from "../lib/codemirror_setup";
import {
  buildBlurHandler,
  buildCodeEditorOptions,
  syncCodeMirrorDocument,
} from "../lib/editor/code_editor";

/**
 * Mounts a CodeMirror editor from `data-*` attributes and optionally pushes
 * `{value}` or `{field, value}` to LiveView on blur when `data-event` is set.
 */
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

/**
 * Generic CodeMirror hook registered as `CodeEditor`.
 */
export default CodeEditor;
