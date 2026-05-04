/**
 * @file Drawflow toolbar actions for zooming, fitting, auto-layout and edit locks.
 */
/**
 * Resets Drawflow pan and zoom to the default viewport.
 * @param {object} editor - Drawflow editor instance.
 * @returns {void}
 */
export function resetZoom(editor) {
  editor.zoom = 1;
  editor.canvas_x = 0;
  editor.canvas_y = 0;
  editor.precanvas.style.transform = "translate(0px, 0px) scale(1)";
  editor.dispatch("zoom", 1);
}

/**
 * Toggles Drawflow between edit and fixed view modes.
 *
 * The active class, title and Heroicon lock class are updated to mirror the new
 * state in the toolbar button.
 *
 * @param {object} editor - Drawflow editor instance.
 * @param {HTMLButtonElement} btn - Toolbar lock button.
 * @returns {void}
 */
export function toggleLock(editor, btn) {
  const isEdit = editor.editor_mode === "edit";
  editor.editor_mode = isEdit ? "fixed" : "edit";
  btn.classList.toggle("df-toolbar-btn-active", !isEdit);
  btn.title = isEdit ? "Unlock (view mode)" : "Toggle lock (edit/view)";

  const icon = btn.querySelector("[data-lock-icon] span");
  if (icon) {
    icon.className = icon.className.replace(
      /hero-lock-\w+/,
      isEdit ? "hero-lock-closed" : "hero-lock-open",
    );
  }
}

/**
 * Wires toolbar button clicks to Drawflow viewport actions.
 *
 * The returned cleanup removes both the DOM click handler and the Drawflow
 * `zoom` listener registered for keeping the label current.
 *
 * @param {object} options - Toolbar dependencies.
 * @param {object} options.editor - Drawflow editor instance.
 * @param {Element | null} options.toolbar - Toolbar root; null returns a no-op cleanup.
 * @param {Function} options.autoLayout - Auto-layout callback.
 * @param {Function} options.fitView - Fit-view callback.
 * @param {Function} options.updateZoomLabel - Zoom label refresh callback.
 * @param {(callback: FrameRequestCallback) => number} [options.requestFrame=requestAnimationFrame] - Frame scheduler.
 * @returns {() => void} Cleanup callback.
 */
export function wireDrawflowToolbar({
  editor,
  toolbar,
  autoLayout,
  fitView,
  updateZoomLabel,
  requestFrame = requestAnimationFrame,
}) {
  if (!toolbar) return () => {};

  updateZoomLabel(editor, toolbar);

  const onZoom = () => updateZoomLabel(editor, toolbar);
  editor.on("zoom", onZoom);

  const onClick = (event) => {
    const btn = event.target.closest("[data-action]");
    if (!btn) return;
    event.stopPropagation();

    switch (btn.dataset.action) {
      case "zoom-in":
        editor.zoom_in();
        break;
      case "zoom-out":
        editor.zoom_out();
        break;
      case "zoom-reset":
        resetZoom(editor);
        break;
      case "fit-view":
        fitView(editor);
        break;
      case "auto-layout":
        autoLayout(editor);
        requestFrame(() => fitView(editor));
        break;
      case "toggle-lock":
        toggleLock(editor, btn);
        break;
    }
  };

  toolbar.addEventListener("click", onClick);

  return () => {
    toolbar.removeEventListener("click", onClick);
    if (editor.removeListener) editor.removeListener("zoom", onZoom);
  };
}
