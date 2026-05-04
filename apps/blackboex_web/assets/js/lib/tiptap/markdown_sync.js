/**
 * @file Markdown synchronization helpers between Tiptap and Phoenix LiveView.
 */
/**
 * Builds the LiveView payload from Tiptap's markdown storage extension.
 * @param {{storage: {markdown: {getMarkdown: Function}}}} editor - Tiptap editor instance.
 * @param {string | undefined} fieldName - Optional form field name for multi-editor pages.
 * @returns {{field?: string, value: string}} Payload sent by editor hooks.
 */
export function markdownPayload(editor, fieldName) {
  const value = editor.storage.markdown.getMarkdown();
  return fieldName ? { field: fieldName, value } : { value };
}

/**
 * Replaces editor content only when LiveView sends markdown that differs locally.
 * @param {{storage: {markdown: {getMarkdown: Function}}, commands: {setContent: Function}} | null | undefined} editor - Tiptap editor instance.
 * @param {string | undefined} newValue - Markdown value received from LiveView.
 * @returns {boolean} True when content was replaced.
 */
export function syncMarkdownContent(editor, newValue) {
  if (newValue === undefined || !editor) return false;
  const current = editor.storage.markdown.getMarkdown();
  if (newValue === current) return false;

  editor.commands.setContent(newValue);
  return true;
}
