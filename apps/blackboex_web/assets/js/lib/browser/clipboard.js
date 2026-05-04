/**
 * @file Shared JavaScript library helpers for browser behavior.
 */
/**
 * Provides copy text from event.
 * @param {unknown} event - Browser or library event payload.
 * @param {unknown} opts - Optional configuration values.
 * @returns {Promise<unknown>} Function result.
 */
export async function copyTextFromEvent(event, opts = {}) {
  const clipboard = opts.clipboard || navigator.clipboard;
  const text = event.detail?.text;
  if (!clipboard || !text) return false;

  await clipboard.writeText(text);
  return true;
}

/**
 * Provides install clipboard handler.
 * @param {unknown} target - Target event source or DOM element.
 * @param {unknown} opts - Optional configuration values.
 * @returns {unknown} Function result.
 */
export function installClipboardHandler(target = window, opts = {}) {
  const handler = (event) => copyTextFromEvent(event, opts);
  target.addEventListener("phx:copy_to_clipboard", handler);
  target.addEventListener("copy_to_clipboard", handler);
  return () => {
    target.removeEventListener("phx:copy_to_clipboard", handler);
    target.removeEventListener("copy_to_clipboard", handler);
  };
}
