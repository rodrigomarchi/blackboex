/**
 * @file Vitest coverage for tiptap editor hook behavior.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { createTiptapEditorHook } from "../../js/hooks/tiptap_editor";
import { cleanupDOM, mountHook } from "../helpers/hook_helper";

describe("TiptapEditor hook", () => {
  afterEach(() => cleanupDOM());

  it("mounts with injected editor wiring, syncs external markdown, and destroys", () => {
    const destroy = vi.fn();
    const setContent = vi.fn();
    const buildExtensions = vi.fn(() => ["extension"]);
    const buildEditorProps = vi.fn(() => ({ attributes: {} }));
    const buildOnUpdate = vi.fn(() => vi.fn());

    class FakeEditor {
      constructor(options) {
        this.options = options;
        this.storage = { markdown: { getMarkdown: () => "old" } };
        this.commands = { setContent };
        this.destroy = destroy;
        this.on = vi.fn();
      }
    }

    const hookDef = createTiptapEditorHook({
      EditorClass: FakeEditor,
      buildExtensions,
      buildEditorProps,
      buildOnUpdate,
    });

    const hook = mountHook(hookDef, {
      attrs: {
        "data-value": "old",
        "data-event": "update_doc",
        "data-field": "body",
        "data-placeholder": "Write",
      },
    });

    expect(buildExtensions).toHaveBeenCalledWith({
      bubbleMenuEl: expect.any(HTMLElement),
      placeholder: "Write",
    });
    expect(hook.editor.options.extensions).toEqual(["extension"]);

    hook.el.dataset.value = "new";
    hook.updated();

    expect(setContent).toHaveBeenCalledWith("new");

    hook.destroyed();
    expect(destroy).toHaveBeenCalledOnce();
    expect(hook.editor).toBeNull();
  });
});
