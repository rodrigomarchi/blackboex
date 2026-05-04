/**
 * @file Pure helpers for the generic CodeMirror LiveView hook.
 */
/**
 * Parses `data-*` attributes from the CodeEditor hook root.
 * @param {HTMLElement} el - Hook root carrying editor configuration in dataset fields.
 * @returns {{language: string, readOnly: boolean, minimal: boolean, eventName: string | undefined, fieldName: string | undefined, initialValue: string}} CodeMirror hook options.
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
 * Builds the CodeMirror blur handler that pushes document content to LiveView.
 *
 * Read-only editors and editors without `data-event` do not push on blur.
 *
 * @param {{pushEvent: (event: string, payload: object) => void}} hook - LiveView hook instance.
 * @param {{readOnly: boolean, eventName?: string, fieldName?: string}} options - Blur push options.
 * @returns {Function | null} CodeMirror DOM blur handler or null when disabled.
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
 * Decides whether an external LiveView value should replace editor content.
 * @param {string | undefined} newValue - Incoming value from `data-value`.
 * @param {string} currentValue - Current CodeMirror document text.
 * @returns {boolean} True when the incoming value is defined and different.
 */
export function shouldSyncDocument(newValue, currentValue) {
  return newValue !== undefined && newValue !== currentValue;
}

/**
 * Replaces the full CodeMirror document when LiveView sends changed content.
 * @param {{state: {doc: {toString: () => string, length: number}}, dispatch: Function} | null} view - CodeMirror EditorView or test double.
 * @param {string | undefined} newValue - Incoming document text.
 * @returns {boolean} True when a CodeMirror transaction was dispatched.
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
