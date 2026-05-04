/**
 * @file Shared JavaScript library helpers for tiptap behavior.
 */
/**
 * Provides markdown payload.
 * @param {unknown} editor - Editor instance used by the helper.
 * @param {unknown} fieldName - fieldName value.
 * @returns {unknown} Function result.
 */
export function markdownPayload(editor, fieldName) {
  const value = editor.storage.markdown.getMarkdown();
  return fieldName ? { field: fieldName, value } : { value };
}

/**
 * Provides sync markdown content.
 * @param {unknown} editor - Editor instance used by the helper.
 * @param {unknown} newValue - newValue value.
 * @returns {unknown} Function result.
 */
export function syncMarkdownContent(editor, newValue) {
  if (newValue === undefined || !editor) return false;
  const current = editor.storage.markdown.getMarkdown();
  if (newValue === current) return false;

  editor.commands.setContent(newValue);
  return true;
}
