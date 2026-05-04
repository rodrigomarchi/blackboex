/**
 * @file Verifies pure helpers behind the generic CodeMirror LiveView hook.
 *
 * Covers parsing `data-*` editor options, deciding whether a LiveView patch
 * should replace the current document, and dispatching a full-document
 * CodeMirror transaction without depending on a real EditorView instance.
 */
import {
  buildCodeEditorOptions,
  shouldSyncDocument,
  syncCodeMirrorDocument,
} from "../../../js/lib/editor/code_editor";

describe("code editor helpers", () => {
  it("builds dataset options with defaults", () => {
    const el = document.createElement("div");
    el.dataset.value = "IO.puts(:ok)";
    el.dataset.language = "elixir";
    el.dataset.readonly = "true";

    expect(buildCodeEditorOptions(el)).toEqual({
      language: "elixir",
      readOnly: true,
      minimal: false,
      eventName: undefined,
      fieldName: undefined,
      initialValue: "IO.puts(:ok)",
    });
  });

  it("detects whether document sync is needed", () => {
    expect(shouldSyncDocument("new", "old")).toBe(true);
    expect(shouldSyncDocument("same", "same")).toBe(false);
    expect(shouldSyncDocument(undefined, "old")).toBe(false);
  });

  it("syncs a CodeMirror-like view", () => {
    const dispatch = vi.fn();
    const view = {
      state: { doc: { length: 3, toString: () => "old" } },
      dispatch,
    };

    syncCodeMirrorDocument(view, "new");

    expect(dispatch).toHaveBeenCalledWith({
      changes: { from: 0, to: 3, insert: "new" },
    });
  });
});
