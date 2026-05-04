/**
 * @file Vitest coverage for editor auto scroll hook hook behavior.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import EditorAutoScroll from "../../../js/hooks/global/editor_auto_scroll_hook";
import { cleanupDOM, mountHook } from "../../helpers/hook_helper";

describe("EditorAutoScroll hook", () => {
  afterEach(() => cleanupDOM());

  it("uses the inner overflow scroller and removes listeners on destroy", () => {
    vi.useFakeTimers();
    const root = document.createElement("div");
    const scroller = document.createElement("div");
    scroller.className = "overflow-y-auto";
    root.appendChild(scroller);

    const hook = mountHook(EditorAutoScroll, root);

    expect(hook.getScroller()).toBe(scroller);

    hook.destroyed();
    vi.useRealTimers();
  });
});
