/**
 * @file Verifies Markdown payload and external-content synchronization helpers.
 *
 * Covers field-aware LiveView payloads from Tiptap markdown storage and the
 * guard that only calls `setContent` when server Markdown differs locally.
 */
import {
  markdownPayload,
  syncMarkdownContent,
} from "../../../js/lib/tiptap/markdown_sync";

describe("markdown sync helpers", () => {
  it("builds field-aware payloads", () => {
    const editor = { storage: { markdown: { getMarkdown: () => "# Title" } } };
    expect(markdownPayload(editor, "body")).toEqual({
      field: "body",
      value: "# Title",
    });
    expect(markdownPayload(editor)).toEqual({ value: "# Title" });
  });

  it("sets content only when changed", () => {
    const setContent = vi.fn();
    const editor = {
      storage: { markdown: { getMarkdown: () => "old" } },
      commands: { setContent },
    };
    expect(syncMarkdownContent(editor, "old")).toBe(false);
    expect(syncMarkdownContent(editor, "new")).toBe(true);
    expect(setContent).toHaveBeenCalledWith("new");
  });
});
