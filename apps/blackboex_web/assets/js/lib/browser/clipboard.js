export async function copyTextFromEvent(event, opts = {}) {
  const clipboard = opts.clipboard || navigator.clipboard;
  const text = event.detail?.text;
  if (!clipboard || !text) return false;

  await clipboard.writeText(text);
  return true;
}

export function installClipboardHandler(target = window, opts = {}) {
  const handler = (event) => copyTextFromEvent(event, opts);
  target.addEventListener("phx:copy_to_clipboard", handler);
  target.addEventListener("copy_to_clipboard", handler);
  return () => {
    target.removeEventListener("phx:copy_to_clipboard", handler);
    target.removeEventListener("copy_to_clipboard", handler);
  };
}
