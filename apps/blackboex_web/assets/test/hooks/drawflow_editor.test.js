/**
 * @file Verifies the DrawflowEditor LiveView hook lifecycle and export bridge.
 *
 * Uses a fake Drawflow class to cover mounting without the optional toolbar,
 * dirty-state listener registration, cleanup of vendor listeners and scheduled
 * work on teardown, and conversion/export through the `save_definition`
 * LiveView event.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanupDOM, mountHook, simulateEvent } from "../helpers/hook_helper";

const drawflowMock = vi.hoisted(() => {
  const instances = [];

  class FakeDrawflow {
    constructor(el) {
      this.el = el;
      this.events = {};
      this.precanvas = document.createElement("div");
      this.canvas_x = 0;
      this.canvas_y = 0;
      this.zoom = 1;
      this.module = "Home";
      this.drawflow = { drawflow: { Home: { data: {} } } };
      this.start = vi.fn(() => el.appendChild(this.precanvas));
      this.clear = vi.fn(() => {
        this.drawflow = { drawflow: { Home: { data: {} } } };
      });
      this.import = vi.fn((data) => {
        this.drawflow = data;
      });
      this.export = vi.fn(() => this.drawflow);
      this.addNodeOutput = vi.fn();
      this.removeNodeOutput = vi.fn();
      instances.push(this);
    }

    on(event, handler) {
      if (!this.events[event]) this.events[event] = [];
      this.events[event].push(handler);
    }

    removeListener(event, handler) {
      this.events[event] = (this.events[event] || []).filter(
        (registered) => registered !== handler,
      );
    }

    dispatch(event, payload) {
      (this.events[event] || []).forEach((handler) => handler(payload));
    }

    getNodeFromId() {
      return null;
    }

    getModuleFromNodeId() {
      return "Home";
    }
  }

  return { FakeDrawflow, instances };
});

vi.mock("../../vendor/drawflow.min.js", () => ({
  default: drawflowMock.FakeDrawflow,
}));

const { default: DrawflowEditor } =
  await import("../../js/hooks/drawflow_editor");

describe("DrawflowEditor hook", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    globalThis.requestAnimationFrame = vi.fn((callback) =>
      setTimeout(callback, 0),
    );
    globalThis.cancelAnimationFrame = vi.fn((id) => clearTimeout(id));
  });

  afterEach(() => {
    vi.useRealTimers();
    cleanupDOM();
    drawflowMock.instances.length = 0;
  });

  it("mounts without the optional toolbar", () => {
    const hook = mountHook(DrawflowEditor);

    expect(drawflowMock.instances[0].start).toHaveBeenCalledOnce();

    hook.destroyed();
  });

  it("removes editor listeners and clears scheduled work on teardown", () => {
    const hook = mountHook(DrawflowEditor);
    const editor = drawflowMock.instances[0];

    editor.dispatch("nodeCreated", "1");
    expect(hook._dataChanged).toBe(true);

    hook.destroyed();
    vi.advanceTimersByTime(100);

    expect(editor.events.nodeCreated).toHaveLength(0);
    expect(editor.clear).toHaveBeenCalledOnce();
    expect(hook.editor).toBeNull();
  });

  it("exports definitions through LiveView events", () => {
    const hook = mountHook(DrawflowEditor);

    simulateEvent(hook, "export_definition", {});

    expect(hook.pushEvent).toHaveBeenCalledWith("save_definition", {
      definition: { version: "1.0", nodes: [], edges: [] },
    });

    hook.destroyed();
  });
});
