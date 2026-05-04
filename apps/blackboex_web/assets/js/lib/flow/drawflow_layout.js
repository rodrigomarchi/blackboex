/**
 * @file Shared JavaScript library helpers for flow behavior.
 */
import dagre from "../../../vendor/dagre.min.js";
import { updateAllOutputLabels } from "./node_catalog";

// Fit canvas so all nodes are visible with padding
/**
 * Provides fit view.
 * @param {unknown} editor - Editor instance used by the helper.
 * @returns {unknown} Function result.
 */
export function fitView(editor) {
  const data = editor.export();
  const homeData = data.drawflow?.Home?.data;
  if (!homeData || Object.keys(homeData).length === 0) return;

  const nodes = Object.values(homeData);
  const padding = 80;

  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity;
  nodes.forEach((n) => {
    const el = document.querySelector(`#node-${n.id}`);
    const w = el ? el.offsetWidth : 200;
    const h = el ? el.offsetHeight : 80;
    if (n.pos_x < minX) minX = n.pos_x;
    if (n.pos_y < minY) minY = n.pos_y;
    if (n.pos_x + w > maxX) maxX = n.pos_x + w;
    if (n.pos_y + h > maxY) maxY = n.pos_y + h;
  });

  const graphW = maxX - minX + padding * 2;
  const graphH = maxY - minY + padding * 2;
  const container = editor.container;
  const containerW = container.clientWidth;
  const containerH = container.clientHeight;

  const scaleX = containerW / graphW;
  const scaleY = containerH / graphH;
  const scale = Math.min(scaleX, scaleY, editor.zoom_max);
  const clampedScale = Math.max(scale, editor.zoom_min);

  editor.zoom = clampedScale;
  editor.canvas_x =
    -(minX - padding) * clampedScale + (containerW - graphW * clampedScale) / 2;
  editor.canvas_y =
    -(minY - padding) * clampedScale + (containerH - graphH * clampedScale) / 2;

  const precanvas = editor.precanvas;
  precanvas.style.transform = `translate(${editor.canvas_x}px, ${editor.canvas_y}px) scale(${clampedScale})`;
  editor.dispatch("zoom", clampedScale);
}

// Auto-layout using dagre (left-to-right hierarchy)
/**
 * Provides auto layout.
 * @param {unknown} editor - Editor instance used by the helper.
 * @param {unknown} opts - Optional configuration values.
 * @returns {unknown} Function result.
 */
export function autoLayout(editor, opts = {}) {
  const data = editor.export();
  const homeData = data.drawflow?.Home?.data;
  if (!homeData || Object.keys(homeData).length === 0) return;

  const nodesep = opts.nodesep || 60;
  const ranksep = opts.ranksep || 120;

  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: "LR", nodesep, ranksep, marginx: 80, marginy: 80 });
  g.setDefaultEdgeLabel(() => ({}));

  // Add nodes with measured dimensions
  Object.keys(homeData).forEach((id) => {
    const el = document.querySelector(`#node-${id}`);
    const w = el ? el.offsetWidth : 200;
    const h = el ? el.offsetHeight : 80;
    g.setNode(id, { width: w + 20, height: h + 20 });
  });

  // Add edges from connections
  Object.entries(homeData).forEach(([id, node]) => {
    Object.values(node.outputs || {}).forEach((output) => {
      output.connections.forEach((conn) => {
        g.setEdge(id, conn.node);
      });
    });
  });

  dagre.layout(g);

  // Apply positions — dagre gives center coords, drawflow uses top-left
  g.nodes().forEach((nodeId) => {
    const layoutNode = g.node(nodeId);
    const dfNode = homeData[nodeId];
    if (dfNode && layoutNode) {
      dfNode.pos_x = layoutNode.x - layoutNode.width / 2;
      dfNode.pos_y = layoutNode.y - layoutNode.height / 2;
    }
  });

  editor.clear();
  editor.import(data);

  // Re-render condition branch labels after import
  setTimeout(() => updateAllOutputLabels(editor), 100);
}

/**
 * Provides update zoom label.
 * @param {unknown} editor - Editor instance used by the helper.
 * @param {unknown} toolbar - toolbar value.
 * @returns {unknown} Function result.
 */
export function updateZoomLabel(editor, toolbar) {
  const label = toolbar.querySelector("[data-zoom-label]");
  if (label) label.textContent = `${Math.round(editor.zoom * 100)}%`;
}
