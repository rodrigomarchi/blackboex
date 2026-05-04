/**
 * @file Verifies the syntax-highlighting language registry for Tiptap code blocks.
 *
 * Ensures Blackboex editor languages, especially Elixir and JavaScript, are
 * present in the exported map and registered into a lowlight instance.
 */
import { describe, expect, it } from "vitest";
import {
  LOWLIGHT_LANGUAGES,
  buildLowlight,
} from "../../../js/lib/tiptap/lowlight_languages";

describe("lowlight languages", () => {
  it("registers the expected editor languages", () => {
    const lowlight = buildLowlight();

    expect(Object.keys(LOWLIGHT_LANGUAGES)).toContain("elixir");
    expect(lowlight.listLanguages()).toContain("elixir");
    expect(lowlight.listLanguages()).toContain("javascript");
  });
});
