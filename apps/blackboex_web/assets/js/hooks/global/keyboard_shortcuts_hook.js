/**
 * @file Global LiveView hook wiring for keyboard shortcuts hook behavior.
 */
import {
  editorShortcutForEvent,
  isCommandPaletteOpen,
} from "../../lib/global/keyboard_shortcuts";

/**
 * LiveView hook for keyboard shortcuts behavior.
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
 * Exports the module default value.
 */
export default KeyboardShortcuts;
