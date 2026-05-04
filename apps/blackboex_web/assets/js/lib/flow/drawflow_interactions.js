import { blackboexToDrawflow } from "./drawflow_converter";

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

export function setSidebarDragData(element, event) {
  event.dataTransfer.setData("node-type", element.dataset.nodeType);
  event.dataTransfer.setData("node-label", element.dataset.nodeLabel);
  event.dataTransfer.setData("node-inputs", element.dataset.nodeInputs);
  event.dataTransfer.setData("node-outputs", element.dataset.nodeOutputs);
}
