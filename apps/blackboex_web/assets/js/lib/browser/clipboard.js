/**
 * @file Browser adapter for LiveView clipboard copy events.
 */
/**
 * Copies text from a LiveView event detail payload to the clipboard.
 * @param {CustomEvent<{text?: string}>} event - Event containing text in `detail.text`.
 * @param {{clipboard?: {writeText: (text: string) => Promise<void>}}} [opts={}] - Clipboard adapter override for tests.
 * @returns {Promise<boolean>} True when text was copied.
 */
export async function copyTextFromEvent(event, opts = {}) {
  const clipboard = opts.clipboard || navigator.clipboard;
  const text = event.detail?.text;
  if (!clipboard || !text) return false;

  await clipboard.writeText(text);
  return true;
}

/**
 * Installs handlers for Phoenix-prefixed and plain clipboard events.
 * @param {Window | EventTarget} [target=window] - Event target receiving copy events.
 * @param {object} [opts={}] - Adapter overrides forwarded to `copyTextFromEvent`.
 * @returns {() => void} Cleanup function that removes both listeners.
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
