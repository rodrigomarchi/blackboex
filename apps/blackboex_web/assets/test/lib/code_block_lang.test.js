/**
 * @file Verifies the compatibility re-export for the Tiptap code block extension.
 *
 * Ensures legacy imports from `js/lib/code_block_lang` receive the same
 * `CodeBlockWithLang` object as the implementation under `js/lib/tiptap`.
 */
import { describe, expect, it } from "vitest";
import { CodeBlockWithLang } from "../../js/lib/code_block_lang";
import { CodeBlockWithLang as TiptapCodeBlockWithLang } from "../../js/lib/tiptap/code_block_lang";

describe("code block language shim", () => {
  it("re-exports the Tiptap code block extension", () => {
    expect(CodeBlockWithLang).toBe(TiptapCodeBlockWithLang);
  });
});
