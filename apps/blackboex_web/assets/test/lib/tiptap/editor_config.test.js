import { describe, expect, it, vi } from "vitest";
import {
  buildTiptapEditorProps,
  buildTiptapOnUpdate,
  shouldShowBubbleMenu,
} from "../../../js/lib/tiptap/editor_config";

describe("tiptap editor config", () => {
  it("hides the bubble menu for code blocks and empty selections", () => {
    expect(
      shouldShowBubbleMenu({
        editor: { isActive: (name) => name === "codeBlock" },
        state: { selection: { empty: false } },
      }),
    ).toBe(false);

    expect(
      shouldShowBubbleMenu({
        editor: { isActive: () => false },
        state: { selection: { empty: true } },
      }),
    ).toBe(false);
  });

  it("handles save and link keyboard shortcuts", () => {
    const editor = { storage: { markdown: { getMarkdown: () => "# doc" } } };
    const pushEvent = vi.fn();
    const promptForLink = vi.fn();
    const props = buildTiptapEditorProps({
      getEditor: () => editor,
      fieldName: "content",
      pushEvent,
      clearDebounce: vi.fn(),
      promptForLinkFn: promptForLink,
    });
    const preventDefault = vi.fn();

    expect(
      props.handleKeyDown(null, { metaKey: true, key: "s", preventDefault }),
    ).toBe(true);
    expect(
      props.handleKeyDown(null, { ctrlKey: true, key: "k", preventDefault }),
    ).toBe(true);

    expect(pushEvent).toHaveBeenCalledWith({
      field: "content",
      value: "# doc",
    });
    expect(promptForLink).toHaveBeenCalledWith(editor);
  });

  it("debounces markdown update pushes", () => {
    vi.useFakeTimers();
    const hook = { pushEvent: vi.fn() };
    const editor = { storage: { markdown: { getMarkdown: () => "updated" } } };
    const onUpdate = buildTiptapOnUpdate({
      hook,
      eventName: "update_doc",
      fieldName: "body",
    });

    onUpdate({ editor });
    vi.advanceTimersByTime(500);

    expect(hook.pushEvent).toHaveBeenCalledWith("update_doc", {
      field: "body",
      value: "updated",
    });
    vi.useRealTimers();
  });
});
