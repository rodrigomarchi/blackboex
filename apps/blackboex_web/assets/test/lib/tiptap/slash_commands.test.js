/**
 * @file Vitest coverage for slash commands library helpers.
 */
import { describe, expect, it } from "vitest";
import {
  COMMANDS,
  createSlashSuggestion,
} from "../../../js/lib/tiptap/slash_commands";
import "../../helpers/hook_helper";

describe("slash commands", () => {
  it("returns the full catalog for an empty query", () => {
    const suggestion = createSlashSuggestion();

    expect(suggestion.items({ query: "" })).toBe(COMMANDS);
  });

  it("filters by title, description, and category", () => {
    const suggestion = createSlashSuggestion();

    expect(
      suggestion.items({ query: "table" }).map((cmd) => cmd.title),
    ).toContain("Table");
    expect(
      suggestion.items({ query: "diagram" }).map((cmd) => cmd.title),
    ).toContain("Mermaid Diagram");
    expect(
      suggestion.items({ query: "alignment" }).map((cmd) => cmd.title),
    ).toContain("Align Left");
  });

  it("handles menu keyboard navigation", () => {
    const suggestion = createSlashSuggestion();
    const renderer = suggestion.render();
    const editor = {
      view: { coordsAtPos: () => ({ left: 10, bottom: 20 }) },
      chain: () => ({
        focus: () => ({
          deleteRange: () => ({ setParagraph: () => ({ run: () => true }) }),
        }),
      }),
    };

    renderer.onStart({
      editor,
      range: { from: 1, to: 2 },
      items: suggestion.items({ query: "text" }),
    });

    expect(document.querySelector(".slash-command-menu")).not.toBeNull();
    expect(
      renderer.onKeyDown({
        event: new KeyboardEvent("keydown", { key: "ArrowDown" }),
      }),
    ).toBe(true);
    expect(
      renderer.onKeyDown({
        event: new KeyboardEvent("keydown", { key: "Escape" }),
      }),
    ).toBe(true);
    expect(document.querySelector(".slash-command-menu")).toBeNull();
  });
});
