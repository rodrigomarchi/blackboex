/**
 * @file Persists and restores sidebar collapsed state.
 */
/**
 * localStorage key used to remember whether the sidebar is collapsed.
 */
export const SIDEBAR_COLLAPSED_KEY = "sidebar-collapsed";

/**
 * Applies persisted collapsed classes to the sidebar root.
 * @param {Element} el - Sidebar root element.
 * @param {Storage} [storage=localStorage] - Storage adapter.
 * @returns {void}
 */
export function applySidebarCollapsedState(el, storage = localStorage) {
  if (storage.getItem(SIDEBAR_COLLAPSED_KEY) === "true") {
    el.classList.add("sidebar-collapsed", "w-14");
    el.classList.remove("w-60");
  }
}

/**
 * Persists the sidebar root's current collapsed class state.
 * @param {Element} el - Sidebar root element.
 * @param {Storage} [storage=localStorage] - Storage adapter.
 * @returns {void}
 */
export function persistSidebarCollapsedState(el, storage = localStorage) {
  storage.setItem(
    SIDEBAR_COLLAPSED_KEY,
    String(el.classList.contains("sidebar-collapsed")),
  );
}
