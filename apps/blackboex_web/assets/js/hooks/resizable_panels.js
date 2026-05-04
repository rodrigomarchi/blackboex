/**
 * @file LiveView hook for persisted drag-resizable playground/page panels.
 */
/**
 * ResizablePanels hook: manages drag-to-resize for playground and page editor panels.
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
 * Panel resize hook registered as `ResizablePanels`.
 */
export default {
  /**
   * Restores stored dimensions and registers every resize handle below the root.
   * @returns {void}
   */
  mounted() {
    this.handles = [];
    this.restoreSizes();
    this.setupHandles();
  },

  /**
   * Removes handle listeners and any active pointer-capture overlay.
   * @returns {void}
   */
  destroyed() {
    this.cleanup();
  },

  /**
   * Finds resize handles and creates drag state for each valid target panel.
   * @returns {void}
   */
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

  /**
   * Starts a resize gesture and binds document-level move/end listeners.
   * @param {MouseEvent | Touch} e - Pointer event that began the drag.
   * @param {object} state - Resize state for one handle/target pair.
   * @returns {void}
   */
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

  /**
   * Applies the next clamped size while a resize gesture is active.
   * @param {MouseEvent | Touch} e - Latest pointer event.
   * @param {object} state - Resize state for one handle/target pair.
   * @returns {void}
   */
  onDrag(e, state) {
    if (!state.dragging) return;

    this.applySize(state, nextPanelSize(state, e));
  },

  /**
   * Writes a panel size through the shared lib helper.
   * @param {object} state - Resize state for one handle/target pair.
   * @param {number} size - Pixel size to apply.
   * @returns {void}
   */
  applySize(state, size) {
    applyPanelSize(state, size, document.documentElement);
  },

  /**
   * Ends a resize gesture, removes temporary document listeners, and persists sizes.
   * @param {object} state - Resize state for one handle/target pair.
   * @param {EventListener} onMouseMove - Document mousemove listener.
   * @param {EventListener} onTouchMove - Document touchmove listener.
   * @param {EventListener} onEnd - Shared gesture end listener.
   * @returns {void}
   */
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

  /**
   * Persists all registered panel dimensions, ignoring unavailable localStorage.
   * @returns {void}
   */
  saveSizes() {
    try {
      savePanelSizes(this.handles, localStorage);
    } catch {
      // localStorage may be unavailable
    }
  },

  /**
   * Restores previously saved panel dimensions and reapplies current constraints.
   * @returns {void}
   */
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

  /**
   * Runs all per-handle cleanups and removes the drag overlay if present.
   * @returns {void}
   */
  cleanup() {
    this.handles.forEach(({ cleanup }) => cleanup());
    this.handles = [];

    if (this.overlay) {
      this.overlay.remove();
      this.overlay = null;
    }
  },
};
