export function commandPaletteDirection(key) {
  if (key === "ArrowDown") return "down";
  if (key === "ArrowUp") return "up";
  return null;
}

export function findSelectedCommand(doc = document) {
  return (
    doc
      .getElementById("command-palette-list")
      ?.querySelector("[class*='bg-base-200']") || null
  );
}

export function scrollSelectedCommandIntoView(doc = document) {
  const selected = findSelectedCommand(doc);
  if (selected) selected.scrollIntoView({ block: "nearest" });
}
