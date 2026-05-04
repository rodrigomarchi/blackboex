/**
 * @file Shared JavaScript library helpers for bootstrap behavior.
 */
/**
 * Provides build admin hooks.
 * @param {object} root0 - Options object.
 * @param {unknown} root0.codeEditor - codeEditor option.
 * @param {unknown} root0.backpexHooks - backpexHooks option.
 * @returns {unknown} Function result.
 */
export function buildAdminHooks({ codeEditor, backpexHooks = {} }) {
  return {
    CodeEditor: codeEditor,
    ...backpexHooks,
  };
}
