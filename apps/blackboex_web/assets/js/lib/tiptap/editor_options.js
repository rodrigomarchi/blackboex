/**
 * @file Parses Tiptap LiveView hook options from data attributes.
 */
/**
 * Reads the editor boot payload embedded in the hook element dataset.
 * @param {HTMLElement} el - Element mounted by the Tiptap LiveView hook.
 * @returns {{content: string, readOnly: boolean, eventName: string | undefined, fieldName: string | undefined, placeholder: string}} Normalized editor options.
 */
export function tiptapDatasetOptions(el) {
  return {
    content: el.dataset.value || "",
    readOnly: el.dataset.readonly === "true",
    eventName: el.dataset.event,
    fieldName: el.dataset.field,
    placeholder: el.dataset.placeholder || "Type '/' for commands...",
  };
}
