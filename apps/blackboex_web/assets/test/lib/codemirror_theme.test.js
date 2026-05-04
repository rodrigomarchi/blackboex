import { describe, expect, it } from "vitest";
import { blackboexEditorTheme } from "../../js/lib/codemirror_theme";

describe("CodeMirror theme", () => {
  it("exports the theme and syntax highlighting extensions", () => {
    expect(blackboexEditorTheme).toHaveLength(2);
  });
});
