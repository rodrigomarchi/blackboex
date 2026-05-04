import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { autocompletion } from "@codemirror/autocomplete";
import { buildExtensions } from "../lib/codemirror_setup";
import { elixirCompletionSource } from "../lib/elixir_completion";
import {
  makeDebouncedCodeSync,
  playgroundEventForKey,
  replaceDocument,
  resolveCompletionItems,
} from "../lib/editor/playground_editor";
import { syncCodeMirrorDocument } from "../lib/editor/code_editor";

const PlaygroundEditor = {
  mounted() {
    const initialValue = this.el.dataset.value || "";

    const extensions = buildExtensions({
      language: "elixir",
      readOnly: false,
      onBlur: null,
      minimal: false,
    });

    // Keyboard shortcuts for playground actions
    const playgroundKeymap = keymap.of([
      {
        key: "Mod-Enter",
        run: () => {
          this.pushEvent(playgroundEventForKey("run"), {});
          return true;
        },
      },
      {
        key: "Mod-s",
        run: () => {
          this.pushEvent(playgroundEventForKey("save"), {});
          return true;
        },
      },
      {
        key: "Mod-Shift-f",
        run: () => {
          this.pushEvent(playgroundEventForKey("format"), {});
          return true;
        },
      },
    ]);

    // Debounced code sync on every change
    const updateListener = EditorView.updateListener.of(
      makeDebouncedCodeSync(this),
    );

    // Server-driven code completion
    const completionExt = autocompletion({
      override: [elixirCompletionSource(this)],
      activateOnTyping: true,
    });

    const state = EditorState.create({
      doc: initialValue,
      extensions: [
        ...extensions,
        playgroundKeymap,
        updateListener,
        completionExt,
      ],
    });

    this.view = new EditorView({ state, parent: this.el });

    // Handle server-pushed formatted code
    this.handleEvent("formatted_code", ({ code }) => {
      replaceDocument(this.view, code);
    });

    // Handle server-pushed completion results (wired in Phase 3)
    this._completionState = { completionResolve: null };
    this.handleEvent("completion_results", ({ items }) => {
      resolveCompletionItems(this._completionState, items);
    });

    // Handle AI agent replacing the whole document after a chat run completes
    this.handleEvent("playground_editor:set_value", ({ code }) => {
      replaceDocument(this.view, code);
    });
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

export default PlaygroundEditor;
