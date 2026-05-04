/**
 * @file Global LiveView hook for editor-shell keyboard shortcuts.
 */
import {
  editorShortcutForEvent,
  isCommandPaletteOpen,
} from "../../lib/global/keyboard_shortcuts";

/**
 * Converts browser keydown events into named LiveView editor-shell actions.
 *
 * The helper checks whether the command palette is open so Escape and Cmd/Ctrl+K
 * map to the correct server event for the current UI state.
 */
const KeyboardShortcuts = {
  mounted() {
    this.handleKeyDown = (event) => {
      const action = editorShortcutForEvent(event, {
        paletteOpen: isCommandPaletteOpen(document),
      });
      if (!action) return;

      event.preventDefault();
      this.pushEvent(action.event, action.payload);
    };

    window.addEventListener("keydown", this.handleKeyDown);
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeyDown);
  },
};

/**
 * Editor-shell keyboard shortcut hook registered as `KeyboardShortcuts`.
 */
export default KeyboardShortcuts;
