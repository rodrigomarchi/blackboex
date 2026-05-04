/**
 * @file State helpers for persisted drag-resizable editor panel dimensions.
 */
/**
 * localStorage key used by the LiveView hooks that remember editor panel sizes.
 */
export const STORAGE_KEY = "playground-panel-sizes";

/**
 * Pixel bounds for the two resize axes supported by the playground/page layouts.
 */
export const PANEL_CONSTRAINTS = {
  vertical: { min: 100, max: 600 },
  horizontal: { min: 200, max: 500 },
};

/**
 * Restricts a requested panel size to the configured range for its axis.
 * @param {"vertical" | "horizontal"} direction - Resize axis selected by the handle.
 * @param {number} size - Requested pixel size.
 * @returns {number} Clamped pixel size.
 */
export function clampPanelSize(direction, size) {
  const constraints = PANEL_CONSTRAINTS[direction];
  return Math.min(Math.max(size, constraints.min), constraints.max);
}

/**
 * Maps a resize axis to the CSS property that stores the panel dimension.
 * @param {"vertical" | "horizontal"} direction - Resize axis selected by the handle.
 * @returns {"height" | "width"} Inline style property to update.
 */
export function panelSizeProperty(direction) {
  return direction === "vertical" ? "height" : "width";
}

/**
 * Reads the pointer coordinate used to compare a drag event against its origin.
 * @param {"vertical" | "horizontal"} direction - Resize axis selected by the handle.
 * @param {MouseEvent | Touch} event - Pointer-like event object from mouse or touch handling.
 * @returns {number} Y coordinate for vertical resizing, X coordinate for horizontal resizing.
 */
export function dragStartPosition(direction, event) {
  return direction === "vertical"
    ? event.clientY || event.pageY
    : event.clientX || event.pageX;
}

/**
 * Captures the current rendered panel dimension before drag deltas are applied.
 * @param {"vertical" | "horizontal"} direction - Resize axis selected by the handle.
 * @param {HTMLElement} target - Panel element being resized.
 * @returns {number} Current panel height or width in pixels.
 */
export function dragStartSize(direction, target) {
  return direction === "vertical" ? target.offsetHeight : target.offsetWidth;
}

/**
 * Computes the next panel size from the drag origin, current pointer position, and limits.
 * @param {{direction: "vertical" | "horizontal", startPos: number, startSize: number}} state - Drag state captured on pointer down.
 * @param {MouseEvent | Touch} event - Latest pointer-like event.
 * @returns {number} Clamped next panel size in pixels.
 */
export function nextPanelSize(state, event) {
  const current = dragStartPosition(state.direction, event);
  const delta = state.startPos - current;
  return clampPanelSize(state.direction, state.startSize + delta);
}

/**
 * Applies a persisted or in-progress size through either a CSS variable or inline style.
 * @param {{direction: "vertical" | "horizontal", target: HTMLElement, cssVar?: string}} state - Resize target and optional CSS variable binding.
 * @param {number} size - Pixel size to write.
 * @param {HTMLElement} root - Element that receives CSS variable updates.
 * @returns {void}
 */
export function applyPanelSize(state, size, root = document.documentElement) {
  const prop = panelSizeProperty(state.direction);
  if (state.cssVar) {
    root.style.setProperty(state.cssVar, size + "px");
  } else {
    state.target.style[prop] = size + "px";
  }
}

/**
 * Persists the rendered size for every registered resize handle by target element id.
 * @param {Array<{state: {direction: "vertical" | "horizontal", target: HTMLElement}}>} handles - Active handles managed by the hook.
 * @param {Storage} storage - Storage adapter, injectable for tests.
 * @returns {void}
 */
export function savePanelSizes(handles, storage = localStorage) {
  const sizes = {};
  handles.forEach(({ state }) => {
    const prop =
      state.direction === "vertical" ? "offsetHeight" : "offsetWidth";
    sizes[state.target.id] = state.target[prop];
  });
  storage.setItem(STORAGE_KEY, JSON.stringify(sizes));
}

/**
 * Loads the last saved panel size map from storage.
 * @param {Storage} storage - Storage adapter, injectable for tests.
 * @returns {Record<string, number> | null} Saved target id to pixel size map, or null when unset.
 */
export function loadPanelSizes(storage = localStorage) {
  const stored = storage.getItem(STORAGE_KEY);
  return stored ? JSON.parse(stored) : null;
}
