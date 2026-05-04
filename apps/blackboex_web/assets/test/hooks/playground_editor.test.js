import { afterEach, describe, expect, it } from "vitest";
import PlaygroundEditor from "../../js/hooks/playground_editor";
import { cleanupDOM, mountHook, simulateEvent } from "../helpers/hook_helper";

describe("PlaygroundEditor hook", () => {
  afterEach(() => cleanupDOM());

  it("mounts CodeMirror and handles server-pushed document replacement", () => {
    const hook = mountHook(PlaygroundEditor, {
      attrs: { "data-value": "IO.puts(:old)" },
    });

    expect(hook.view.state.doc.toString()).toBe("IO.puts(:old)");

    simulateEvent(hook, "formatted_code", { code: "IO.puts(:new)" });

    expect(hook.view.state.doc.toString()).toBe("IO.puts(:new)");

    hook.destroyed();
    expect(hook.view).toBeNull();
  });
});
