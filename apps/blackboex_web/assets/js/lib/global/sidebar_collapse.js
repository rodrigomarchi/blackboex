/**
 * @file Shared JavaScript library helpers for global behavior.
 */
/**
 * Provides sidebar collapsed key.
 */
export const SIDEBAR_COLLAPSED_KEY = "sidebar-collapsed";

/**
 * Provides apply sidebar collapsed state.
 * @param {unknown} el - DOM element used by the helper.
 * @param {unknown} storage - Storage adapter used by the helper.
 * @returns {unknown} Function result.
 */
export function applySidebarCollapsedState(el, storage = localStorage) {
  if (storage.getItem(SIDEBAR_COLLAPSED_KEY) === "true") {
    el.classList.add("sidebar-collapsed", "w-14");
    el.classList.remove("w-60");
  }
}

/**
 * Provides persist sidebar collapsed state.
 * @param {unknown} el - DOM element used by the helper.
 * @param {unknown} storage - Storage adapter used by the helper.
 * @returns {unknown} Function result.
 */
export function persistSidebarCollapsedState(el, storage = localStorage) {
  storage.setItem(
    SIDEBAR_COLLAPSED_KEY,
    String(el.classList.contains("sidebar-collapsed")),
  );
}
