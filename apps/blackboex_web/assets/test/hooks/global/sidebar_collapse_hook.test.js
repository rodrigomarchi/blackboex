/**
 * @file Verifies SidebarCollapse restoration and DOM-event persistence.
 *
 * Covers applying the stored `sidebar-collapsed` state on mount and writing the
 * latest class state back to localStorage when the component dispatches
 * `sidebar:toggled`.
 */
import { afterEach, describe, expect, it } from "vitest";
import SidebarCollapse from "../../../js/hooks/global/sidebar_collapse_hook";
import {
  cleanupDOM,
  mockLocalStorage,
  mountHook,
} from "../../helpers/hook_helper";

describe("SidebarCollapse hook", () => {
  afterEach(() => cleanupDOM());

  it("restores and persists collapsed state", () => {
    const storage = mockLocalStorage();
    storage.setItem("sidebar-collapsed", "true");
    const el = document.createElement("div");
    document.body.appendChild(el);

    mountHook(SidebarCollapse, el);
    expect(el.classList.contains("sidebar-collapsed")).toBe(true);

    el.classList.remove("sidebar-collapsed");
    el.dispatchEvent(new Event("sidebar:toggled"));

    expect(storage.getItem("sidebar-collapsed")).toBe("false");
  });
});
