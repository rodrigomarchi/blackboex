/**
 * @file Vitest coverage for hook maps library helpers.
 */
import { describe, expect, it } from "vitest";
import { buildAdminHooks } from "../../../js/lib/bootstrap/hook_maps";

describe("hook maps", () => {
  it("registers CodeEditor in the admin hook map alongside Backpex hooks", () => {
    const codeEditor = { mounted() {} };
    const backpexHook = { mounted() {} };

    expect(
      buildAdminHooks({
        codeEditor,
        backpexHooks: { BackpexInline: backpexHook },
      }),
    ).toEqual({
      CodeEditor: codeEditor,
      BackpexInline: backpexHook,
    });
  });
});
