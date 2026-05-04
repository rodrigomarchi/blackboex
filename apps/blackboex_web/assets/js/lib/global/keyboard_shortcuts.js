/**
 * @file Maps browser keyboard events to API editor LiveView shortcut events.
 */
/**
 * Converts a keydown event into the LiveView shortcut action it represents.
 * @param {KeyboardEvent} event - Browser keydown event.
 * @param {{paletteOpen?: boolean}} [opts={}] - Current UI shortcut context.
 * @returns {{event: string, payload: object} | null} LiveView event payload or null.
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
 * Checks whether the command palette is currently rendered.
 * @param {Document} [doc=document] - Document to inspect.
 * @returns {boolean} True when a command palette root is present.
 */
export function isCommandPaletteOpen(doc = document) {
  return Boolean(doc.querySelector("[data-command-palette]"));
}
