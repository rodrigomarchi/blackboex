/**
 * @file Verifies topbar integration with Phoenix page-loading events.
 *
 * Covers configuration, delayed `show(300)`, `hide()` on stop, and the uninstall
 * function used by tests or future entrypoints that need to detach listeners.
 */
import { describe, expect, it, vi } from "vitest";
import { installTopbar } from "../../../js/lib/bootstrap/topbar";

describe("installTopbar", () => {
  it("wires Phoenix page loading events and returns an uninstall function", () => {
    const target = new EventTarget();
    const topbar = {
      config: vi.fn(),
      show: vi.fn(),
      hide: vi.fn(),
    };

    const uninstall = installTopbar(topbar, target, {
      barColors: { 0: "#fff" },
    });
    target.dispatchEvent(new Event("phx:page-loading-start"));
    target.dispatchEvent(new Event("phx:page-loading-stop"));
    uninstall();
    target.dispatchEvent(new Event("phx:page-loading-start"));

    expect(topbar.config).toHaveBeenCalledWith({ barColors: { 0: "#fff" } });
    expect(topbar.show).toHaveBeenCalledTimes(1);
    expect(topbar.show).toHaveBeenCalledWith(300);
    expect(topbar.hide).toHaveBeenCalledOnce();
  });
});
