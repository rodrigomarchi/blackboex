/**
 * @file Vitest coverage for code editor hook behavior.
 */
import { afterEach, describe, expect, it } from "vitest";
import CodeEditor from "../../js/hooks/code_editor";
import { cleanupDOM, mountHook } from "../helpers/hook_helper";

describe("CodeEditor hook", () => {
  afterEach(() => cleanupDOM());

  it("mounts, syncs dataset changes, and destroys CodeMirror", () => {
    const hook = mountHook(CodeEditor, {
      attrs: {
        "data-language": "json",
        "data-readonly": "true",
        "data-minimal": "true",
        "data-value": '{"ok":true}',
      },
    });

    expect(hook.view.state.doc.toString()).toBe('{"ok":true}');

    hook.el.dataset.value = '{"ok":false}';
    hook.updated();

    expect(hook.view.state.doc.toString()).toBe('{"ok":false}');

    hook.destroyed();
    expect(hook.view).toBeNull();
  });
});
