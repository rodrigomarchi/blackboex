/**
 * @file Verifies Drawflow viewport helpers used by toolbar and execution layout.
 *
 * The tests pin zoom label formatting and the `fitView` behavior that measures
 * rendered node dimensions, updates the precanvas transform, and dispatches a
 * Drawflow zoom event after fitting the graph into the canvas container.
 */
import { describe, expect, it, vi } from "vitest";
import { fitView, updateZoomLabel } from "../../../js/lib/flow/drawflow_layout";

describe("drawflow layout", () => {
  it("updates toolbar zoom labels", () => {
    const toolbar = document.createElement("div");
    toolbar.innerHTML = "<span data-zoom-label></span>";

    updateZoomLabel({ zoom: 1.25 }, toolbar);

    expect(toolbar.querySelector("[data-zoom-label]").textContent).toBe("125%");
  });

  it("fits the canvas around exported nodes", () => {
    document.body.innerHTML = '<div id="node-1"></div>';
    const nodeEl = document.getElementById("node-1");
    Object.defineProperty(nodeEl, "offsetWidth", { value: 200 });
    Object.defineProperty(nodeEl, "offsetHeight", { value: 80 });
    const container = document.createElement("div");
    Object.defineProperty(container, "clientWidth", { value: 800 });
    Object.defineProperty(container, "clientHeight", { value: 600 });
    const editor = {
      zoom_min: 0.2,
      zoom_max: 1.6,
      container,
      precanvas: { style: {} },
      dispatch: vi.fn(),
      export: () => ({
        drawflow: { Home: { data: { 1: { id: 1, pos_x: 100, pos_y: 50 } } } },
      }),
    };

    fitView(editor);

    expect(editor.zoom).toBeGreaterThan(0);
    expect(editor.precanvas.style.transform).toContain("scale");
    expect(editor.dispatch).toHaveBeenCalledWith("zoom", editor.zoom);
  });
});
