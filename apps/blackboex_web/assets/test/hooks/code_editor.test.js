/**
 * @file Verifies the CodeEditor LiveView hook lifecycle.
 *
 * Covers mounting CodeMirror from `data-language`, `data-readonly`,
 * `data-minimal`, and `data-value`, syncing later LiveView dataset patches, and
 * destroying the EditorView on hook teardown.
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
