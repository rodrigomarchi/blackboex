/**
 * @file Global LiveView hook wiring for command palette nav hook behavior.
 */
import {
  commandPaletteDirection,
  scrollSelectedCommandIntoView,
} from "../../lib/global/command_palette";

/**
 * LiveView hook for command palette nav behavior.
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
 * Exports the module default value.
 */
export default CommandPaletteNav;
