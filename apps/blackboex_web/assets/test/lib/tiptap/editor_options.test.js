import { describe, expect, it } from "vitest";
import { tiptapDatasetOptions } from "../../../js/lib/tiptap/editor_options";

describe("tiptap editor options", () => {
  it("parses editor options from dataset with defaults", () => {
    const el = document.createElement("div");
    el.dataset.value = "# Title";
    el.dataset.readonly = "true";
    el.dataset.event = "save";
    el.dataset.field = "body";

    expect(tiptapDatasetOptions(el)).toEqual({
      content: "# Title",
      readOnly: true,
      eventName: "save",
      fieldName: "body",
      placeholder: "Type '/' for commands...",
    });
  });
});
