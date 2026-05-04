/**
 * @file Verifies the ResizablePanels LiveView hook lifecycle.
 *
 * Covers restoring persisted panel sizes from `playground-panel-sizes`, applying
 * them to target elements, registering `[data-resize-handle]` controls, and
 * removing handle state during hook teardown.
 */
import { afterEach, describe, expect, it } from "vitest";
import ResizablePanels from "../../js/hooks/resizable_panels";
import {
  cleanupDOM,
  mockLocalStorage,
  mountHook,
} from "../helpers/hook_helper";

describe("ResizablePanels hook", () => {
  afterEach(() => cleanupDOM());

  it("restores persisted sizes and registers resize handles", () => {
    const storage = mockLocalStorage();
    storage.setItem("playground-panel-sizes", JSON.stringify({ panel: 350 }));
    document.body.innerHTML = `
      <div id="root">
        <div data-resize-handle data-resize-direction="vertical" data-resize-target="panel"></div>
      </div>
      <div id="panel"></div>
    `;

    const hook = mountHook(ResizablePanels, document.getElementById("root"));

    expect(document.getElementById("panel").style.height).toBe("350px");
    expect(hook.handles).toHaveLength(1);
    hook.destroyed();
    expect(hook.handles).toHaveLength(0);
  });
});
