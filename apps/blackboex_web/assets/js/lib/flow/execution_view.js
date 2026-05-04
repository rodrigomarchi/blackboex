/**
 * @file Shared JavaScript library helpers for flow behavior.
 */
import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { buildExtensions } from "../codemirror_setup";

/**
 * Provides exec status colors.
 */
/**
 * Provides exec status colors.
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
 * Provides exec status labels.
 */
/**
 * Provides exec status labels.
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
 * Provides format execution duration.
 * @param {unknown} ms - ms value.
 * @returns {unknown} Function result.
 */
export function formatExecutionDuration(ms) {
  if (ms === null || ms === undefined) return "";
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
}

/**
 * Provides build execution data node html.
 * @param {unknown} options - Configuration values for the helper.
 * @param {unknown} nodeKey - nodeKey value.
 * @returns {unknown} Function result.
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
 * Provides mount execution code mirror views.
 * @param {unknown} root - Root element or document used for lookup.
 * @returns {unknown} Function result.
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
 * Provides destroy execution code mirror views.
 * @param {unknown} views - views value.
 * @returns {unknown} Function result.
 */
export function destroyExecutionCodeMirrorViews(views) {
  views.forEach((view) => view.destroy());
}

/**
 * Provides apply execution highlights.
 * @param {unknown} nodes - nodes value.
 * @param {unknown} root - Root element or document used for lookup.
 * @returns {unknown} Function result.
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
      "font-size:9px",
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
        ? `<span style="color:#94a3b8;font-size:8px;font-family:ui-monospace,monospace">${duration}</span>`
        : "");
    el.appendChild(pill);
  });
}
