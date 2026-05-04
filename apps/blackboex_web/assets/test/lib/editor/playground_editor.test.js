/**
 * @file Verifies Playground editor event mapping and completion handoff.
 *
 * Covers the keyboard shortcut to LiveView event names used by the hook and the
 * one-shot resolver state that bridges server-pushed Elixir completion results
 * back into CodeMirror's async completion source.
 */
import {
  playgroundEventForKey,
  resolveCompletionItems,
} from "../../../js/lib/editor/playground_editor";

describe("playground editor helpers", () => {
  it("maps keyboard shortcuts to LiveView events", () => {
    expect(playgroundEventForKey("run")).toBe("run");
    expect(playgroundEventForKey("save")).toBe("save_code");
    expect(playgroundEventForKey("format")).toBe("format_code");
  });

  it("resolves pending completion items once", () => {
    const resolver = vi.fn();
    const state = { completionResolve: resolver };

    resolveCompletionItems(state, [{ label: "Enum.map/2" }]);

    expect(resolver).toHaveBeenCalledWith([{ label: "Enum.map/2" }]);
    expect(state.completionResolve).toBeNull();
  });
});
