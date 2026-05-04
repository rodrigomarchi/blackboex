/**
 * @file Shared JavaScript library helpers for ui behavior.
 */
/**
 * Provides storage key.
 */
export const STORAGE_KEY = "playground-panel-sizes";

/**
 * Provides panel constraints.
 */
/**
 * Provides panel constraints.
 */
export const PANEL_CONSTRAINTS = {
  vertical: { min: 100, max: 600 },
  horizontal: { min: 200, max: 500 },
};

/**
 * Provides clamp panel size.
 * @param {unknown} direction - direction value.
 * @param {unknown} size - size value.
 * @returns {unknown} Function result.
 */
export function clampPanelSize(direction, size) {
  const constraints = PANEL_CONSTRAINTS[direction];
  return Math.min(Math.max(size, constraints.min), constraints.max);
}

/**
 * Provides panel size property.
 * @param {unknown} direction - direction value.
 * @returns {unknown} Function result.
 */
export function panelSizeProperty(direction) {
  return direction === "vertical" ? "height" : "width";
}

/**
 * Provides drag start position.
 * @param {unknown} direction - direction value.
 * @param {unknown} event - Browser or library event payload.
 * @returns {unknown} Function result.
 */
export function dragStartPosition(direction, event) {
  return direction === "vertical"
    ? event.clientY || event.pageY
    : event.clientX || event.pageX;
}

/**
 * Provides drag start size.
 * @param {unknown} direction - direction value.
 * @param {unknown} target - Target event source or DOM element.
 * @returns {unknown} Function result.
 */
export function dragStartSize(direction, target) {
  return direction === "vertical" ? target.offsetHeight : target.offsetWidth;
}

/**
 * Provides next panel size.
 * @param {unknown} state - State object used by the helper.
 * @param {unknown} event - Browser or library event payload.
 * @returns {unknown} Function result.
 */
export function nextPanelSize(state, event) {
  const current = dragStartPosition(state.direction, event);
  const delta = state.startPos - current;
  return clampPanelSize(state.direction, state.startSize + delta);
}

/**
 * Provides apply panel size.
 * @param {unknown} state - State object used by the helper.
 * @param {unknown} size - size value.
 * @param {unknown} root - Root element or document used for lookup.
 * @returns {unknown} Function result.
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
 * Provides save panel sizes.
 * @param {unknown} handles - handles value.
 * @param {unknown} storage - Storage adapter used by the helper.
 * @returns {unknown} Function result.
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
 * Provides load panel sizes.
 * @param {unknown} storage - Storage adapter used by the helper.
 * @returns {unknown} Function result.
 */
export function loadPanelSizes(storage = localStorage) {
  const stored = storage.getItem(STORAGE_KEY);
  return stored ? JSON.parse(stored) : null;
}
