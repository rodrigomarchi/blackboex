/**
 * @file LiveView hook wiring for resizable panels behavior.
 */
/**
 * ResizablePanels hook — manages drag-to-resize for playground panels.
 *
 * Looks for elements with [data-resize-handle] inside the hook element.
 * Each handle needs:
 *   - data-resize-direction="vertical" | "horizontal"
 *   - data-resize-target="<id of the panel to resize>"
 * Optional:
 *   - data-resize-css-var="--name"  writes the size to this CSS custom
 *     property on :root instead of the target's inline style, so LiveView
 *     re-renders can't reset the user-dragged size. The target element
 *     should then declare e.g. style="height: var(--name, 320px);".
 *
 * Vertical handles control height, horizontal handles control width.
 * Sizes are persisted to localStorage and restored on mount.
 */
import {
  applyPanelSize,
  clampPanelSize,
  dragStartPosition,
  dragStartSize,
  loadPanelSizes,
  nextPanelSize,
  panelSizeProperty,
  savePanelSizes,
} from "../lib/ui/resizable_panels";

/**
 * Exports the module default value.
 */
export default {
  mounted() {
    this.handles = [];
    this.restoreSizes();
    this.setupHandles();
  },

  destroyed() {
    this.cleanup();
  },

  setupHandles() {
    const handles = this.el.querySelectorAll("[data-resize-handle]");

    handles.forEach((handle) => {
      const direction = handle.dataset.resizeDirection;
      const targetId = handle.dataset.resizeTarget;
      const cssVar = handle.dataset.resizeCssVar || null;
      const target = document.getElementById(targetId);

      if (!target) return;

      const state = {
        handle,
        direction,
        target,
        cssVar,
        dragging: false,
        startPos: 0,
        startSize: 0,
      };

      const onMouseDown = (e) => this.startDrag(e, state);
      const onTouchStart = (e) => this.startDrag(e.touches[0], state);

      handle.addEventListener("mousedown", onMouseDown);
      handle.addEventListener("touchstart", onTouchStart, { passive: true });

      this.handles.push({
        state,
        cleanup: () => {
          handle.removeEventListener("mousedown", onMouseDown);
          handle.removeEventListener("touchstart", onTouchStart);
        },
      });
    });
  },

  startDrag(e, state) {
    e.preventDefault();
    state.dragging = true;
    state.startPos = dragStartPosition(state.direction, e);
    state.startSize = dragStartSize(state.direction, state.target);

    // Add overlay to prevent iframe/editor from capturing events
    this.overlay = document.createElement("div");
    this.overlay.style.cssText =
      "position:fixed;inset:0;z-index:9999;cursor:" +
      (state.direction === "vertical" ? "row-resize" : "col-resize");
    document.body.appendChild(this.overlay);

    const onMouseMove = (e) => this.onDrag(e, state);
    const onTouchMove = (e) => this.onDrag(e.touches[0], state);
    const onEnd = () => this.endDrag(state, onMouseMove, onTouchMove, onEnd);

    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("touchmove", onTouchMove, { passive: true });
    document.addEventListener("mouseup", onEnd);
    document.addEventListener("touchend", onEnd);
  },

  onDrag(e, state) {
    if (!state.dragging) return;

    this.applySize(state, nextPanelSize(state, e));
  },

  applySize(state, size) {
    applyPanelSize(state, size, document.documentElement);
  },

  endDrag(state, onMouseMove, onTouchMove, onEnd) {
    state.dragging = false;

    if (this.overlay) {
      this.overlay.remove();
      this.overlay = null;
    }

    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("touchmove", onTouchMove);
    document.removeEventListener("mouseup", onEnd);
    document.removeEventListener("touchend", onEnd);

    this.saveSizes();
  },

  saveSizes() {
    try {
      savePanelSizes(this.handles, localStorage);
    } catch {
      // localStorage may be unavailable
    }
  },

  restoreSizes() {
    try {
      const sizes = loadPanelSizes(localStorage);
      if (!sizes) return;

      Object.entries(sizes).forEach(([id, size]) => {
        const el = document.getElementById(id);
        if (!el) return;

        const handle = this.el.querySelector(`[data-resize-target="${id}"]`);
        if (!handle) return;

        const direction = handle.dataset.resizeDirection;
        const cssVar = handle.dataset.resizeCssVar || null;
        const clamped = clampPanelSize(direction, size);

        if (cssVar) {
          document.documentElement.style.setProperty(cssVar, clamped + "px");
        } else {
          el.style[panelSizeProperty(direction)] = clamped + "px";
        }
      });
    } catch {
      // Ignore parse errors
    }
  },

  cleanup() {
    this.handles.forEach(({ cleanup }) => cleanup());
    this.handles = [];

    if (this.overlay) {
      this.overlay.remove();
      this.overlay = null;
    }
  },
};
