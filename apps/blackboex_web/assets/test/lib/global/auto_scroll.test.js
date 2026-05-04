/**
 * @file Vitest coverage for auto scroll library helpers.
 */
import { describe, expect, it } from "vitest";
import {
  findEditorScroller,
  isAtBottom,
  scrollChatToBottom,
  scrollElementToBottom,
} from "../../../js/lib/global/auto_scroll";

describe("auto scroll helpers", () => {
  it("detects bottom proximity with a threshold", () => {
    const el = { scrollHeight: 1000, scrollTop: 880, clientHeight: 100 };

    expect(isAtBottom(el)).toBe(true);
    expect(isAtBottom({ ...el, scrollTop: 700 })).toBe(false);
  });

  it("scrolls chat container and nested overflow panes", () => {
    const root = document.createElement("div");
    const nested = document.createElement("div");
    nested.className = "overflow-y-auto";
    root.appendChild(nested);

    Object.defineProperty(root, "scrollHeight", { value: 500 });
    Object.defineProperty(nested, "scrollHeight", { value: 300 });

    scrollChatToBottom(root);

    expect(root.scrollTop).toBe(500);
    expect(nested.scrollTop).toBe(300);
  });

  it("finds editor scrollers", () => {
    const root = document.createElement("div");
    root.innerHTML = `<div class="overflow-y-auto"></div>`;

    expect(findEditorScroller(root)).toBe(root.firstElementChild);
    scrollElementToBottom(root.firstElementChild);
  });
});
