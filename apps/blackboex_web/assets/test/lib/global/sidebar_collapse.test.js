import { describe, expect, it, vi } from "vitest";
import {
  SIDEBAR_COLLAPSED_KEY,
  applySidebarCollapsedState,
  persistSidebarCollapsedState,
} from "../../../js/lib/global/sidebar_collapse";

describe("sidebar collapse helpers", () => {
  it("restores collapsed classes from storage", () => {
    const el = document.createElement("aside");
    el.className = "w-60";
    const storage = { getItem: vi.fn(() => "true") };

    applySidebarCollapsedState(el, storage);

    expect(el.classList.contains("sidebar-collapsed")).toBe(true);
    expect(el.classList.contains("w-14")).toBe(true);
    expect(el.classList.contains("w-60")).toBe(false);
  });

  it("persists the current collapsed state", () => {
    const el = document.createElement("aside");
    el.classList.add("sidebar-collapsed");
    const storage = { setItem: vi.fn() };

    persistSidebarCollapsedState(el, storage);

    expect(storage.setItem).toHaveBeenCalledWith(SIDEBAR_COLLAPSED_KEY, "true");
  });
});
