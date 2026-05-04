/**
 * @file Renders flow execution overlays, status pills, and read-only JSON
 * output viewers inside Drawflow nodes.
 */
import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { buildExtensions } from "../codemirror_setup";

/**
 * Hex colors used for execution status borders, dots, and CSS variables.
 */
export const EXEC_STATUS_COLORS = {
  completed: "#10b981",
  failed: "#ef4444",
  running: "#3b82f6",
  pending: "#6b7280",
  halted: "#f59e0b",
  skipped: "#a855f7",
};

/**
 * Human-readable labels rendered in execution status pills.
 */
export const EXEC_STATUS_LABELS = {
  completed: "completed",
  failed: "failed",
  running: "running",
  pending: "pending",
  halted: "halted",
  skipped: "skipped",
};

/**
 * Formats execution durations for compact node status pills.
 * @param {number | null | undefined} ms - Duration in milliseconds.
 * @returns {string} Empty string for absent durations, otherwise ms or seconds.
 */
export function formatExecutionDuration(ms) {
  if (ms === null || ms === undefined) return "";
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
}

/**
 * Builds Drawflow node HTML for a transient execution output data node.
 *
 * JSON output is base64 encoded into the DOM so Drawflow can import it as an
 * HTML string and `mountExecutionCodeMirrorViews/1` can later mount a read-only
 * CodeMirror viewer in place.
 *
 * @param {object} execution - Execution payload for a node.
 * @param {string | undefined} execution.status - Node execution status.
 * @param {object | Array<object> | string | number | boolean | null | undefined} execution.output - JSON-serializable node output.
 * @param {string | object | null | undefined} execution.error - Error displayed above the output.
 * @param {string} nodeKey - Stable key used as the CodeMirror mount identifier.
 * @returns {string} Drawflow node HTML string.
 */
export function buildExecutionDataNodeHtml({ status, output, error }, nodeKey) {
  const json =
    output !== null && output !== undefined
      ? JSON.stringify(output, null, 2)
      : null;
  const b64 = json ? btoa(unescape(encodeURIComponent(json))) : null;

  return `<div class="df-exec-dn" data-status="${status || "pending"}">
    ${error ? `<div class="df-exec-dn-error">${String(error).slice(0, 200)}</div>` : ""}
    ${b64 ? `<div class="df-exec-dn-cm" data-exec-key="${nodeKey}" data-b64="${b64}"></div>` : ""}
  </div>`;
}

/**
 * Mounts read-only JSON CodeMirror views into unmounted execution data nodes.
 *
 * Each placeholder is marked with `data-cm-mounted` so repeated calls do not
 * double-mount editors after LiveView or Drawflow DOM updates.
 *
 * @param {ParentNode} [root=document] - Root used to find `.df-exec-dn-cm` placeholders.
 * @returns {Array<{destroy: Function}>} Mounted CodeMirror views for cleanup.
 */
export function mountExecutionCodeMirrorViews(root = document) {
  const views = [];

  root
    .querySelectorAll(".df-exec-dn-cm:not([data-cm-mounted])")
    .forEach((el) => {
      el.dataset.cmMounted = "1";
      let json;
      try {
        json = decodeURIComponent(escape(atob(el.dataset.b64 || "")));
      } catch {
        json = "";
      }

      const extensions = buildExtensions({
        language: "json",
        readOnly: true,
        minimal: true,
        onBlur: null,
      });
      const view = new EditorView({
        state: EditorState.create({ doc: json, extensions }),
        parent: el,
      });
      views.push(view);
    });

  return views;
}

/**
 * Destroys CodeMirror views created for an execution overlay.
 * @param {Array<{destroy: Function}>} views - Views returned by `mountExecutionCodeMirrorViews`.
 * @returns {void}
 */
export function destroyExecutionCodeMirrorViews(views) {
  views.forEach((view) => view.destroy());
}

/**
 * Adds status classes, color variables, and floating status pills to nodes.
 *
 * Flow execution ids use canonical `n123` ids while Drawflow DOM nodes use
 * `#node-123`, so ids are normalized before lookup.
 *
 * @param {Array<{id: string, status: string, duration_ms?: number}>} nodes - Execution node summaries.
 * @param {Document | Element} [root=document] - Root used to find Drawflow node elements.
 * @returns {void}
 */
export function applyExecutionHighlights(nodes, root = document) {
  nodes.forEach(({ id, status, duration_ms: durationMs }) => {
    const dfId = id.startsWith("n") ? id.slice(1) : id;
    const el = root.querySelector(`#node-${dfId}`);
    if (!el) return;

    const color = EXEC_STATUS_COLORS[status] || EXEC_STATUS_COLORS.pending;
    const label = EXEC_STATUS_LABELS[status] || status;
    const duration = formatExecutionDuration(durationMs);

    el.classList.add("df-exec-highlight");
    el.style.setProperty("--exec-color", color);

    const pill = root.createElement("div");
    pill.className = "df-exec-status-pill";
    pill.style.cssText = [
      "position:absolute",
      "top:-20px",
      "left:50%",
      "transform:translateX(-50%)",
      "display:inline-flex",
      "align-items:center",
      "gap:4px",
      "background:hsl(var(--card))",
      `border:1.5px solid ${color}55`,
      "border-radius:999px",
      "padding:2px 8px",
      "font-size:var(--content-font-drawflow-data)",
      "font-weight:700",
      "font-family:ui-sans-serif,system-ui,sans-serif",
      "white-space:nowrap",
      "pointer-events:none",
      "z-index:20",
      "box-shadow:0 2px 8px rgba(0,0,0,.5)",
      "line-height:1.8",
    ].join(";");
    pill.innerHTML =
      `<span style="width:5px;height:5px;border-radius:50%;background:${color};display:inline-block;flex-shrink:0"></span>` +
      `<span style="color:${color}">${label}</span>` +
      (duration
        ? `<span style="color:#94a3b8;font-size:var(--content-font-drawflow-data);font-family:ui-monospace,monospace">${duration}</span>`
        : "");
    el.appendChild(pill);
  });
}
