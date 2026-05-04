/**
 * @file Verifies Drawflow toolbar wiring and editor state mutations.
 *
 * Covers the optional toolbar case, click listener cleanup, Drawflow zoom event
 * unsubscription, zoom reset side effects, and lock button state changes used by
 * the visual flow editor toolbar.
 */
import { describe, expect, it, vi } from "vitest";
import {
  resetZoom,
  toggleLock,
  wireDrawflowToolbar,
} from "../../../js/lib/flow/drawflow_toolbar";

describe("drawflow toolbar", () => {
  it("does nothing when the toolbar is absent", () => {
    const cleanup = wireDrawflowToolbar({
      editor: {},
      toolbar: null,
      autoLayout: vi.fn(),
      fitView: vi.fn(),
      updateZoomLabel: vi.fn(),
    });

    expect(cleanup).toEqual(expect.any(Function));
    expect(() => cleanup()).not.toThrow();
  });

  it("wires toolbar actions and removes listeners on cleanup", () => {
    const toolbar = document.createElement("div");
    toolbar.innerHTML = `<button data-action="fit-view"></button>`;
    const editor = {
      on: vi.fn(),
      removeListener: vi.fn(),
      zoom_in: vi.fn(),
      zoom_out: vi.fn(),
    };
    const fitView = vi.fn();
    const cleanup = wireDrawflowToolbar({
      editor,
      toolbar,
      autoLayout: vi.fn(),
      fitView,
      updateZoomLabel: vi.fn(),
    });

    toolbar.querySelector("button").click();
    cleanup();
    toolbar.querySelector("button").click();

    expect(fitView).toHaveBeenCalledOnce();
    expect(editor.removeListener).toHaveBeenCalledWith(
      "zoom",
      expect.any(Function),
    );
  });

  it("resets zoom and toggles lock button state", () => {
    const editor = {
      zoom: 2,
      canvas_x: 20,
      canvas_y: 40,
      editor_mode: "edit",
      precanvas: { style: {} },
      dispatch: vi.fn(),
    };
    const btn = document.createElement("button");
    btn.innerHTML = `<span data-lock-icon><span class="hero-lock-open"></span></span>`;

    resetZoom(editor);
    toggleLock(editor, btn);

    expect(editor.zoom).toBe(1);
    expect(editor.canvas_x).toBe(0);
    expect(editor.dispatch).toHaveBeenCalledWith("zoom", 1);
    expect(editor.editor_mode).toBe("fixed");
    expect(btn.classList.contains("df-toolbar-btn-active")).toBe(false);
  });
});
