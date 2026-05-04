/**
 * @file Shared JavaScript library helpers for editor behavior.
 */
/**
 * Provides build code editor options.
 * @param {unknown} el - DOM element used by the helper.
 * @returns {unknown} Function result.
 */
export function buildCodeEditorOptions(el) {
  return {
    language: el.dataset.language || "text",
    readOnly: el.dataset.readonly === "true",
    minimal: el.dataset.minimal === "true",
    eventName: el.dataset.event,
    fieldName: el.dataset.field,
    initialValue: el.dataset.value || "",
  };
}

/**
 * Provides build blur handler.
 * @param {unknown} hook - LiveView hook instance or test double.
 * @param {unknown} options2 - options2 value.
 * @returns {unknown} Function result.
 */
export function buildBlurHandler(hook, { readOnly, eventName, fieldName }) {
  if (readOnly || !eventName) return null;

  return (_event, view) => {
    const value = view.state.doc.toString();
    const payload = fieldName ? { field: fieldName, value } : { value };
    hook.pushEvent(eventName, payload);
  };
}

/**
 * Provides should sync document.
 * @param {unknown} newValue - newValue value.
 * @param {unknown} currentValue - currentValue value.
 * @returns {unknown} Function result.
 */
export function shouldSyncDocument(newValue, currentValue) {
  return newValue !== undefined && newValue !== currentValue;
}

/**
 * Provides sync code mirror document.
 * @param {unknown} view - CodeMirror editor view.
 * @param {unknown} newValue - newValue value.
 * @returns {unknown} Function result.
 */
export function syncCodeMirrorDocument(view, newValue) {
  if (!view) return false;
  const currentValue = view.state.doc.toString();
  if (!shouldSyncDocument(newValue, currentValue)) return false;

  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: newValue },
  });
  return true;
}
