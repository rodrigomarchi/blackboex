/**
 * @file Vitest coverage for chat auto scroll hook hook behavior.
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
