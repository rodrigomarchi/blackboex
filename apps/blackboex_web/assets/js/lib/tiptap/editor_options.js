/**
 * @file Shared JavaScript library helpers for tiptap behavior.
 */
/**
 * Provides tiptap dataset options.
 * @param {unknown} el - DOM element used by the helper.
 * @returns {unknown} Function result.
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
