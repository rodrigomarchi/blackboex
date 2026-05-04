export function buildAdminHooks({ codeEditor, backpexHooks = {} }) {
  return {
    CodeEditor: codeEditor,
    ...backpexHooks,
  };
}
