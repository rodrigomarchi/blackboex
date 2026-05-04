/**
 * @file Shared JavaScript library helpers for global behavior.
 */
/**
 * Provides command palette direction.
 * @param {unknown} key - key value.
 * @returns {unknown} Function result.
 */
export function commandPaletteDirection(key) {
  if (key === "ArrowDown") return "down";
  if (key === "ArrowUp") return "up";
  return null;
}

/**
 * Provides find selected command.
 * @param {unknown} doc - Document used for DOM lookup.
 * @returns {unknown} Function result.
 */
export function findSelectedCommand(doc = document) {
  return (
    doc
      .getElementById("command-palette-list")
      ?.querySelector("[class*='bg-base-200']") || null
  );
}

/**
 * Provides scroll selected command into view.
 * @param {unknown} doc - Document used for DOM lookup.
 * @returns {unknown} Function result.
 */
export function scrollSelectedCommandIntoView(doc = document) {
  const selected = findSelectedCommand(doc);
  if (selected) selected.scrollIntoView({ block: "nearest" });
}
