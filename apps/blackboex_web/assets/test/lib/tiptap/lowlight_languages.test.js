/**
 * @file Vitest coverage for lowlight languages library helpers.
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
