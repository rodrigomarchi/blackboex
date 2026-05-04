/**
 * @file Vitest coverage for drawflow interactions library helpers.
 */
import { describe, expect, it, vi } from "vitest";
import {
  createNodeFromDrop,
  loadDrawflowDefinition,
  setSidebarDragData,
} from "../../../js/lib/flow/drawflow_interactions";

describe("drawflow interactions", () => {
  it("loads BlackboexFlow definitions through the converter", () => {
    const editor = { import: vi.fn() };
    const convert = vi.fn(() => ({ drawflow: { Home: { data: {} } } }));
    const definition = JSON.stringify({ version: "1.0", nodes: [], edges: [] });

    expect(loadDrawflowDefinition(editor, definition, vi.fn(), convert)).toBe(
      true,
    );
    expect(editor.import).toHaveBeenCalledWith({
      drawflow: { Home: { data: {} } },
    });
  });

  it("creates a node from drop data", () => {
    const root = document.createElement("div");
    root.getBoundingClientRect = () => ({ left: 10, top: 20 });
    const editor = {
      canvas_x: 0,
      canvas_y: 0,
      zoom: 1,
      precanvas: { getBoundingClientRect: () => ({ left: 1, top: 2 }) },
      addNode: vi.fn(),
    };
    const event = {
      preventDefault: vi.fn(),
      clientX: 111,
      clientY: 222,
      dataTransfer: {
        getData: vi.fn(
          (key) =>
            ({
              "node-type": "http_request",
              "node-inputs": "1",
              "node-outputs": "2",
            })[key],
        ),
      },
    };

    expect(createNodeFromDrop(root, editor, event, (type) => type)).toBe(true);

    expect(editor.addNode).toHaveBeenCalledWith(
      "http_request",
      1,
      2,
      100,
      200,
      "http_request",
      {},
      "http_request",
    );
  });

  it("copies sidebar node metadata into drag data", () => {
    const element = document.createElement("div");
    element.dataset.nodeType = "condition";
    element.dataset.nodeLabel = "Condition";
    element.dataset.nodeInputs = "1";
    element.dataset.nodeOutputs = "2";
    const event = { dataTransfer: { setData: vi.fn() } };

    setSidebarDragData(element, event);

    expect(event.dataTransfer.setData).toHaveBeenCalledWith(
      "node-type",
      "condition",
    );
    expect(event.dataTransfer.setData).toHaveBeenCalledWith(
      "node-outputs",
      "2",
    );
  });
});
