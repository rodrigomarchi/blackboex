import { describe, expect, it } from "vitest";
import { buildExtensions } from "../../js/lib/codemirror_setup";

describe("codemirror setup", () => {
  it("builds full editor extensions with language support", () => {
    const extensions = buildExtensions({
      language: "json",
      readOnly: false,
      minimal: false,
      onBlur: null,
    });

    expect(extensions.length).toBeGreaterThan(8);
  });

  it("keeps minimal read-only editors smaller", () => {
    const full = buildExtensions({
      language: "json",
      readOnly: true,
      minimal: false,
      onBlur: null,
    });
    const minimal = buildExtensions({
      language: "json",
      readOnly: true,
      minimal: true,
      onBlur: null,
    });

    expect(minimal.length).toBeLessThan(full.length);
  });
});
