/**
 * @file Drawflow interaction helpers for loading definitions and creating
 * canvas nodes from sidebar drag/drop metadata.
 */
import { blackboexToDrawflow } from "./drawflow_converter";

/**
 * Imports a serialized flow definition into Drawflow.
 *
 * Current BlackboexFlow definitions are converted before import. Legacy raw
 * Drawflow JSON is accepted unchanged so older persisted definitions can still
 * load in the editor.
 *
 * @param {{import: Function}} editor - Drawflow editor instance.
 * @param {string | null | undefined} definition - JSON string from the hook dataset.
 * @param {(type: string, outputCount: number, data?: object) => string} htmlBuilder - Node HTML renderer used by the converter.
 * @param {(definition: object, htmlBuilder: Function) => object} [convert=blackboexToDrawflow] - BlackboexFlow-to-Drawflow converter.
 * @returns {boolean} True when a valid definition was imported.
 */
export function loadDrawflowDefinition(
  editor,
  definition,
  htmlBuilder,
  convert = blackboexToDrawflow,
) {
  if (!definition) return false;

  try {
    const parsed = JSON.parse(definition);
    if (parsed && parsed.version && parsed.nodes) {
      editor.import(convert(parsed, htmlBuilder));
      return true;
    }
    if (parsed && parsed.drawflow) {
      editor.import(parsed);
      return true;
    }
  } catch {
    return false;
  }

  return false;
}

/**
 * Converts browser drop coordinates into Drawflow canvas coordinates.
 *
 * The calculation compensates for the root element position, the translated
 * precanvas position, current pan offsets, and current zoom.
 *
 * @param {Element} root - Drawflow root element.
 * @param {{precanvas: Element, canvas_x: number, canvas_y: number, zoom: number}} editor - Drawflow editor viewport state.
 * @param {DragEvent} event - Drop event.
 * @returns {{x: number, y: number}} Coordinates in Drawflow canvas space.
 */
export function drawflowDropPosition(root, editor, event) {
  const rootRect = root.getBoundingClientRect();
  const canvasRect = editor.precanvas.getBoundingClientRect();

  return {
    x:
      (event.clientX - rootRect.left - canvasRect.left + editor.canvas_x) /
      editor.zoom,
    y:
      (event.clientY - rootRect.top - canvasRect.top + editor.canvas_y) /
      editor.zoom,
  };
}

/**
 * Creates a Drawflow node from sidebar drag metadata.
 *
 * Sidebar items provide node type and port counts through `dataTransfer`.
 * Missing node type means the drop was unrelated and no editor mutation occurs.
 *
 * @param {Element} root - Drawflow root element.
 * @param {{addNode: Function, precanvas: Element, canvas_x: number, canvas_y: number, zoom: number}} editor - Drawflow editor instance.
 * @param {DragEvent} event - Drop event carrying node metadata.
 * @param {(type: string, outputs: number, data: object) => string} htmlBuilder - Node HTML renderer.
 * @returns {boolean} True when a node was added to the editor.
 */
export function createNodeFromDrop(root, editor, event, htmlBuilder) {
  event.preventDefault();
  const type = event.dataTransfer.getData("node-type");
  const inputs = parseInt(event.dataTransfer.getData("node-inputs") || "1", 10);
  const outputs = parseInt(
    event.dataTransfer.getData("node-outputs") || "1",
    10,
  );

  if (!type) return false;

  const { x, y } = drawflowDropPosition(root, editor, event);
  editor.addNode(
    type,
    inputs,
    outputs,
    x,
    y,
    type,
    {},
    htmlBuilder(type, outputs, {}),
  );
  return true;
}

/**
 * Copies sidebar node metadata into a dragstart event.
 *
 * The Drawflow drop handler reads these keys to decide which node type to
 * create and how many input/output ports it should start with.
 *
 * @param {HTMLElement} element - Sidebar palette item with node dataset fields.
 * @param {DragEvent} event - Dragstart event with a writable dataTransfer object.
 * @returns {void}
 */
export function setSidebarDragData(element, event) {
  event.dataTransfer.setData("node-type", element.dataset.nodeType);
  event.dataTransfer.setData("node-label", element.dataset.nodeLabel);
  event.dataTransfer.setData("node-inputs", element.dataset.nodeInputs);
  event.dataTransfer.setData("node-outputs", element.dataset.nodeOutputs);
}
