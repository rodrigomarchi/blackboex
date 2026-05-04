/**
 * @file Keyboard and DOM helpers for command palette navigation.
 */
/**
 * Converts arrow key names into command palette navigation directions.
 * @param {string} key - KeyboardEvent key value.
 * @returns {"up" | "down" | null} Navigation direction for handled keys.
 */
export function commandPaletteDirection(key) {
  if (key === "ArrowDown") return "down";
  if (key === "ArrowUp") return "up";
  return null;
}

/**
 * Finds the currently highlighted command palette item.
 * @param {Document} [doc=document] - Document containing the palette list.
 * @returns {Element | null} Selected command element.
 */
export function findSelectedCommand(doc = document) {
  return (
    doc
      .getElementById("command-palette-list")
      ?.querySelector("[class*='bg-base-200']") || null
  );
}

/**
 * Keeps the highlighted command visible after keyboard navigation or patches.
 * @param {Document} [doc=document] - Document containing the palette list.
 * @returns {void}
 */
export function scrollSelectedCommandIntoView(doc = document) {
  const selected = findSelectedCommand(doc);
  if (selected) selected.scrollIntoView({ block: "nearest" });
}
