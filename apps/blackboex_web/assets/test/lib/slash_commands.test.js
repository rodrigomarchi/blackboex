/**
 * @file Vitest coverage for slash commands library helpers.
 */
import { describe, expect, it } from "vitest";
import { COMMANDS } from "../../js/lib/slash_commands";
import { COMMANDS as TiptapCommands } from "../../js/lib/tiptap/slash_commands";

describe("slash command shim", () => {
  it("re-exports the Tiptap slash command catalog", () => {
    expect(COMMANDS).toBe(TiptapCommands);
  });
});
