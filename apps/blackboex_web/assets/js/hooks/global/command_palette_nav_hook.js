/**
 * @file Global LiveView hook for keyboard navigation inside the command palette.
 */
import {
  commandPaletteDirection,
  scrollSelectedCommandIntoView,
} from "../../lib/global/command_palette";

/**
 * Focuses the palette input, translates arrow keys to LiveView navigation
 * events, and keeps the selected command visible after patches.
 */
const CommandPaletteNav = {
  mounted() {
    this.el.focus();

    this.handleKeyDown = (event) => {
      const direction = commandPaletteDirection(event.key);
      if (!direction) return;

      event.preventDefault();
      this.pushEvent("command_palette_navigate", { direction });
    };

    this.el.addEventListener("keydown", this.handleKeyDown);
  },

  updated() {
    this.el.focus();
    scrollSelectedCommandIntoView(document);
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.handleKeyDown);
  },
};

/**
 * Command palette navigation hook registered as `CommandPaletteNav`.
 */
export default CommandPaletteNav;
