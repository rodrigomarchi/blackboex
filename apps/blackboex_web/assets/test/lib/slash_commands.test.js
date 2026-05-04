/**
 * @file Verifies the compatibility re-export for Tiptap slash commands.
 *
 * Ensures legacy imports from `js/lib/slash_commands` receive the same command
 * catalog object as the implementation under `js/lib/tiptap`.
 */
import { describe, expect, it } from "vitest";
import { COMMANDS } from "../../js/lib/slash_commands";
import { COMMANDS as TiptapCommands } from "../../js/lib/tiptap/slash_commands";

describe("slash command shim", () => {
  it("re-exports the Tiptap slash command catalog", () => {
    expect(COMMANDS).toBe(TiptapCommands);
  });
});
