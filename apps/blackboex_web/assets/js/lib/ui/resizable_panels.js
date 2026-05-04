export const STORAGE_KEY = "playground-panel-sizes";

export const PANEL_CONSTRAINTS = {
  vertical: { min: 100, max: 600 },
  horizontal: { min: 200, max: 500 },
};

export function clampPanelSize(direction, size) {
  const constraints = PANEL_CONSTRAINTS[direction];
  return Math.min(Math.max(size, constraints.min), constraints.max);
}

export function panelSizeProperty(direction) {
  return direction === "vertical" ? "height" : "width";
}

export function dragStartPosition(direction, event) {
  return direction === "vertical"
    ? event.clientY || event.pageY
    : event.clientX || event.pageX;
}

export function dragStartSize(direction, target) {
  return direction === "vertical" ? target.offsetHeight : target.offsetWidth;
}

export function nextPanelSize(state, event) {
  const current = dragStartPosition(state.direction, event);
  const delta = state.startPos - current;
  return clampPanelSize(state.direction, state.startSize + delta);
}

export function applyPanelSize(state, size, root = document.documentElement) {
  const prop = panelSizeProperty(state.direction);
  if (state.cssVar) {
    root.style.setProperty(state.cssVar, size + "px");
  } else {
    state.target.style[prop] = size + "px";
  }
}

export function savePanelSizes(handles, storage = localStorage) {
  const sizes = {};
  handles.forEach(({ state }) => {
    const prop =
      state.direction === "vertical" ? "offsetHeight" : "offsetWidth";
    sizes[state.target.id] = state.target[prop];
  });
  storage.setItem(STORAGE_KEY, JSON.stringify(sizes));
}

export function loadPanelSizes(storage = localStorage) {
  const stored = storage.getItem(STORAGE_KEY);
  return stored ? JSON.parse(stored) : null;
}
