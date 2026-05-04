/**
 * @file Pure helpers for the Playground Elixir CodeMirror LiveView hook.
 */
/**
 * Maps internal shortcut actions to Playground LiveView event names.
 * @param {"run" | "save" | "format"} action - Shortcut action name.
 * @returns {string | undefined} LiveView event name for the action.
 */
export function playgroundEventForKey(action) {
  return {
    run: "run",
    save: "save_code",
    format: "format_code",
  }[action];
}

/**
 * Replaces the entire Playground editor document.
 * @param {{state: {doc: {length: number}}, dispatch: Function} | null} view - CodeMirror EditorView or test double.
 * @param {string} code - New Elixir source code.
 * @returns {boolean} True when the editor was updated.
 */
export function replaceDocument(view, code) {
  if (!view || typeof code !== "string") return false;

  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: code },
  });
  return true;
}

/**
 * Resolves the pending server-backed completion request once.
 * @param {{completionResolve: Function | null}} state - Completion state stored on the hook.
 * @param {Array<object>} items - Completion items returned by LiveView.
 * @returns {boolean} True when a pending resolver was called.
 */
export function resolveCompletionItems(state, items) {
  if (!state.completionResolve) return false;
  state.completionResolve(items);
  state.completionResolve = null;
  return true;
}

/**
 * Builds a CodeMirror update listener that debounces `"update_code"` pushes.
 * @param {{pushEvent: (event: string, payload: object) => void}} hook - Playground LiveView hook.
 * @param {number} [delay=300] - Debounce delay in milliseconds.
 * @returns {(update: {docChanged: boolean, state: {doc: {toString: () => string}}}) => void} CodeMirror update listener.
 */
export function makeDebouncedCodeSync(hook, delay = 300) {
  let debounceTimer = null;
  return (update) => {
    if (!update.docChanged) return;

    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      hook.pushEvent("update_code", { value: update.state.doc.toString() });
    }, delay);
  };
}
