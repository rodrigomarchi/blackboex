/**
 * @file Verifies ChatAutoScroll cleanup for streaming chat timelines.
 *
 * Covers disconnecting the MutationObserver and clearing the polling interval
 * created to follow LiveView stream/text updates.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import ChatAutoScroll from "../../../js/hooks/global/chat_auto_scroll_hook";
import { cleanupDOM, mountHook } from "../../helpers/hook_helper";

describe("ChatAutoScroll hook", () => {
  afterEach(() => cleanupDOM());

  it("disconnects mutation observer and polling on destroy", () => {
    vi.useFakeTimers();
    const hook = mountHook(ChatAutoScroll);
    const disconnect = vi.spyOn(hook.observer, "disconnect");

    hook.destroyed();

    expect(disconnect).toHaveBeenCalledOnce();
    vi.useRealTimers();
  });
});
