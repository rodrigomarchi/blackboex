import { describe, expect, it, vi } from "vitest";
import {
  LANG_LABELS,
  enqueueRender,
  fitSvg,
  getMermaid,
  setMermaidLoader,
} from "../../../js/lib/tiptap/code_block_lang";

describe("code block language helpers", () => {
  it("normalizes SVG dimensions for responsive mermaid previews", () => {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("width", "320");
    svg.setAttribute("height", "200");

    fitSvg(svg);

    expect(svg.getAttribute("viewBox")).toBe("0 0 320 200");
    expect(svg.getAttribute("width")).toBeNull();
    expect(svg.style.width).toBe("100%");
  });

  it("exposes human-friendly language labels", () => {
    expect(LANG_LABELS.elixir).toBe("Elixir");
    expect(LANG_LABELS.mermaid).toBe("Mermaid");
  });

  it("loads and reuses the injected mermaid module", async () => {
    const mermaid = {
      initialize: vi.fn(),
      render: vi.fn(async (id, text) => ({
        svg: `<svg id="${id}">${text}</svg>`,
      })),
    };
    const loader = vi.fn(async () => mermaid);
    setMermaidLoader(loader);

    expect(await getMermaid()).toBe(mermaid);
    expect(await getMermaid()).toBe(mermaid);
    expect(loader).toHaveBeenCalledOnce();
    await expect(enqueueRender("m1", "graph TD")).resolves.toEqual({
      svg: '<svg id="m1">graph TD</svg>',
    });
  });
});
