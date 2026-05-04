/**
 * @file Verifies the KeyboardShortcuts window listener lifecycle.
 *
 * Covers translating a global Cmd/Ctrl+K keydown into `toggle_command_palette`,
 * preventing the browser default, and removing the listener on hook teardown.
 */
import { mountHook, cleanupDOM } from "../../helpers/hook_helper";
import KeyboardShortcuts from "../../../js/hooks/global/keyboard_shortcuts_hook";

describe("KeyboardShortcuts hook", () => {
  afterEach(() => cleanupDOM());

  it("pushes shortcut events and prevents default", () => {
    const hook = mountHook(KeyboardShortcuts);
    const event = new KeyboardEvent("keydown", {
      key: "k",
      metaKey: true,
      bubbles: true,
      cancelable: true,
    });

    window.dispatchEvent(event);

    expect(event.defaultPrevented).toBe(true);
    expect(hook.pushEvent).toHaveBeenCalledWith("toggle_command_palette", {});
  });

  it("removes the window listener on destroy", () => {
    const hook = mountHook(KeyboardShortcuts);
    hook.destroyed();
    window.dispatchEvent(
      new KeyboardEvent("keydown", { key: "s", metaKey: true, bubbles: true }),
    );
    expect(hook.pushEvent).not.toHaveBeenCalled();
  });
});
