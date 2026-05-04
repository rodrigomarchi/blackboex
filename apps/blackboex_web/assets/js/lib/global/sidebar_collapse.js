export const SIDEBAR_COLLAPSED_KEY = "sidebar-collapsed";

export function applySidebarCollapsedState(el, storage = localStorage) {
  if (storage.getItem(SIDEBAR_COLLAPSED_KEY) === "true") {
    el.classList.add("sidebar-collapsed", "w-14");
    el.classList.remove("w-60");
  }
}

export function persistSidebarCollapsedState(el, storage = localStorage) {
  storage.setItem(
    SIDEBAR_COLLAPSED_KEY,
    String(el.classList.contains("sidebar-collapsed")),
  );
}
