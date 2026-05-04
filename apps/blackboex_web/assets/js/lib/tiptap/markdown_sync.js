export function markdownPayload(editor, fieldName) {
  const value = editor.storage.markdown.getMarkdown();
  return fieldName ? { field: fieldName, value } : { value };
}

export function syncMarkdownContent(editor, newValue) {
  if (newValue === undefined || !editor) return false;
  const current = editor.storage.markdown.getMarkdown();
  if (newValue === current) return false;

  editor.commands.setContent(newValue);
  return true;
}
