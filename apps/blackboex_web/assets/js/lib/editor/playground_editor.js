/**
 * @file Shared JavaScript library helpers for editor behavior.
 */
/**
 * Provides playground event for key.
 * @param {unknown} action - action value.
 * @returns {unknown} Function result.
 */
export function playgroundEventForKey(action) {
  return {
    run: "run",
    save: "save_code",
    format: "format_code",
  }[action];
}

/**
 * Provides replace document.
 * @param {unknown} view - CodeMirror editor view.
 * @param {unknown} code - code value.
 * @returns {unknown} Function result.
 */
export function replaceDocument(view, code) {
  if (!view || typeof code !== "string") return false;

  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: code },
  });
  return true;
}

/**
 * Provides resolve completion items.
 * @param {unknown} state - State object used by the helper.
 * @param {unknown} items - items value.
 * @returns {unknown} Function result.
 */
export function resolveCompletionItems(state, items) {
  if (!state.completionResolve) return false;
  state.completionResolve(items);
  state.completionResolve = null;
  return true;
}

/**
 * Provides make debounced code sync.
 * @param {unknown} hook - LiveView hook instance or test double.
 * @param {unknown} delay - delay value.
 * @returns {unknown} Function result.
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
