import { describe, expect, it } from "vitest";
import { CodeBlockWithLang } from "../../js/lib/code_block_lang";
import { CodeBlockWithLang as TiptapCodeBlockWithLang } from "../../js/lib/tiptap/code_block_lang";

describe("code block language shim", () => {
  it("re-exports the Tiptap code block extension", () => {
    expect(CodeBlockWithLang).toBe(TiptapCodeBlockWithLang);
  });
});
