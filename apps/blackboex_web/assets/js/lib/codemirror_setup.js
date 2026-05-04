/**
 * @file Builds reusable CodeMirror extension sets for Blackboex editor fields.
 */
/**
 * @typedef {object} CodeMirrorExtensionOptions
 * @property {string} language
 * @property {boolean} readOnly
 * @property {Function | undefined} onBlur
 * @property {boolean} minimal
 */
import { keymap, EditorView } from "@codemirror/view";
import { defaultKeymap, indentWithTab } from "@codemirror/commands";
import { closeBrackets } from "@codemirror/autocomplete";
import { bracketMatching, indentOnInput } from "@codemirror/language";
import { json, jsonParseLinter } from "@codemirror/lang-json";
import { markdown } from "@codemirror/lang-markdown";
import { linter } from "@codemirror/lint";
import { elixir } from "codemirror-lang-elixir";
import { EditorState } from "@codemirror/state";
import {
  lineNumbers,
  highlightActiveLineGutter,
  highlightActiveLine,
} from "@codemirror/view";
import { blackboexEditorTheme } from "./codemirror_theme";

/**
 * Builds the CodeMirror extension list for a requested editor mode.
 *
 * The common baseline includes keymaps, bracket helpers and the app theme.
 * Language extensions, JSON linting, read-only state and compact UI are added
 * based on the hook options.
 *
 * @param {CodeMirrorExtensionOptions} options - Language, read-only and UI options.
 * @returns {Array<object>} CodeMirror extensions in initialization order.
 */
export function buildExtensions({ language, readOnly, onBlur, minimal }) {
  const extensions = [
    bracketMatching(),
    indentOnInput(),
    closeBrackets(),
    keymap.of([...defaultKeymap, indentWithTab]),
    blackboexEditorTheme,
  ];

  if (!minimal) {
    extensions.push(lineNumbers());
    extensions.push(highlightActiveLineGutter());
    extensions.push(highlightActiveLine());
  }

  if (language === "elixir") {
    extensions.push(elixir());
  } else if (language === "json") {
    extensions.push(json());
    extensions.push(linter(jsonParseLinter()));
  } else if (language === "markdown") {
    extensions.push(markdown());
  }

  if (readOnly) {
    extensions.push(EditorState.readOnly.of(true));
    extensions.push(EditorView.editable.of(false));
  }

  if (onBlur) {
    extensions.push(EditorView.domEventHandlers({ blur: onBlur }));
  }

  return extensions;
}
