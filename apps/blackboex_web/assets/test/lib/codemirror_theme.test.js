/**
 * @file Verifies the CodeMirror theme bundle exported to editor setup code.
 *
 * The theme module must provide both the editor theme extension and syntax
 * highlighting extension as the pair consumed by `buildExtensions`.
 */
import { describe, expect, it } from "vitest";
import { blackboexEditorTheme } from "../../js/lib/codemirror_theme";

describe("CodeMirror theme", () => {
  it("exports the theme and syntax highlighting extensions", () => {
    expect(blackboexEditorTheme).toHaveLength(2);
  });
});
