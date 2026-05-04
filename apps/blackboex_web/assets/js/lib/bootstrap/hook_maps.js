/**
 * @file Hook map builders shared by Phoenix LiveSocket entrypoints.
 */
/**
 * Builds the hook map used by the Backpex admin LiveSocket.
 *
 * @param {object} root0 - Options object.
 * @param {object} root0.codeEditor - CodeEditor hook registered as `"CodeEditor"`.
 * @param {object} root0.backpexHooks - Hooks exposed by Backpex.
 * @returns {object} Combined admin hook map.
 */
export function buildAdminHooks({ codeEditor, backpexHooks = {} }) {
  return {
    CodeEditor: codeEditor,
    ...backpexHooks,
  };
}
