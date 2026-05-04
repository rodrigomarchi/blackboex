import { afterEach, describe, expect, it } from "vitest";
import AutoFocus from "../../../js/hooks/global/auto_focus_hook";
import { cleanupDOM, mountHook } from "../../helpers/hook_helper";

describe("AutoFocus hook", () => {
  afterEach(() => cleanupDOM());

  it("focuses on mount and update", () => {
    const input = document.createElement("input");
    document.body.appendChild(input);
    const hook = mountHook(AutoFocus, input);

    expect(document.activeElement).toBe(input);
    document.body.focus();
    hook.updated();

    expect(document.activeElement).toBe(input);
  });
});
