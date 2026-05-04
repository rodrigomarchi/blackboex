import {
  editorShortcutForEvent,
  isCommandPaletteOpen,
} from "../../lib/global/keyboard_shortcuts";

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

export default KeyboardShortcuts;
