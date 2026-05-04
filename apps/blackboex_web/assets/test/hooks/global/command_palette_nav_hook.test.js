/**
 * @file Verifies CommandPaletteNav keyboard event forwarding.
 *
 * Covers ArrowDown and ArrowUp becoming `command_palette_navigate` LiveView
 * pushes while unrelated keys, such as Enter, are ignored by the hook.
 */
import { afterEach, describe, expect, it } from "vitest";
import CommandPaletteNav from "../../../js/hooks/global/command_palette_nav_hook";
import {
  cleanupDOM,
  getPushEvents,
  mountHook,
} from "../../helpers/hook_helper";

describe("CommandPaletteNav hook", () => {
  afterEach(() => cleanupDOM());

  it("pushes navigation events for arrow keys", () => {
    const el = document.createElement("div");
    document.body.appendChild(el);
    const hook = mountHook(CommandPaletteNav, el);

    el.dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }),
    );
    el.dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }),
    );
    el.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true }),
    );

    expect(getPushEvents(hook, "command_palette_navigate")).toEqual([
      { direction: "down" },
      { direction: "up" },
    ]);
  });
});
