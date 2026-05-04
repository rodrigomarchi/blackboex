/**
 * @file Shared JavaScript library helpers for global behavior.
 */
/**
 * Provides editor shortcut for event.
 * @param {unknown} event - Browser or library event payload.
 * @param {unknown} opts - Optional configuration values.
 * @returns {unknown} Function result.
 */
export function editorShortcutForEvent(event, opts = {}) {
  const isMeta = event.metaKey || event.ctrlKey;

  if (isMeta && event.key === "k") {
    return { event: "toggle_command_palette", payload: {} };
  }

  if (opts.paletteOpen) {
    return event.key === "Escape"
      ? { event: "toggle_command_palette", payload: {} }
      : null;
  }

  if (isMeta && event.key === "s") return { event: "save", payload: {} };
  if (isMeta && event.key === "l") return { event: "toggle_chat", payload: {} };
  if (isMeta && event.key === "j") {
    return { event: "toggle_bottom_panel", payload: {} };
  }
  if (isMeta && event.key === "i" && !event.shiftKey) {
    return { event: "toggle_config", payload: {} };
  }
  if (isMeta && event.key === "Enter") {
    return { event: "send_request", payload: {} };
  }
  if (event.key === "Escape") return { event: "close_panels", payload: {} };

  return null;
}

/**
 * Provides is command palette open.
 * @param {unknown} doc - Document used for DOM lookup.
 * @returns {unknown} Function result.
 */
export function isCommandPaletteOpen(doc = document) {
  return Boolean(doc.querySelector("[data-command-palette]"));
}
