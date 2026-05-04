/**
 * @file Verifies shared behavior across the chat and editor auto-scroll hooks.
 *
 * Covers ChatAutoScroll observer/poll cleanup and EditorAutoScroll's selection
 * of the inner editor scroller, keeping the two hook variants tested together.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import ChatAutoScroll from "../../../js/hooks/global/chat_auto_scroll_hook";
import EditorAutoScroll from "../../../js/hooks/global/editor_auto_scroll_hook";
import { cleanupDOM, mountHook } from "../../helpers/hook_helper";

describe("auto-scroll hooks", () => {
  afterEach(() => cleanupDOM());

  it("ChatAutoScroll cleans up observer and polling", () => {
    vi.useFakeTimers();
    const el = document.createElement("div");
    document.body.appendChild(el);
    const hook = mountHook(ChatAutoScroll, el);
    const disconnect = vi.spyOn(hook.observer, "disconnect");

    hook.destroyed();

    expect(disconnect).toHaveBeenCalledOnce();
    vi.useRealTimers();
  });

  it("EditorAutoScroll finds the inner editor scroller", () => {
    vi.useFakeTimers();
    const root = document.createElement("div");
    const scroller = document.createElement("div");
    scroller.className = "overflow-y-auto";
    root.appendChild(scroller);
    document.body.appendChild(root);

    const hook = mountHook(EditorAutoScroll, root);

    expect(hook.getScroller()).toBe(scroller);
    hook.destroyed();
    vi.useRealTimers();
  });
});
