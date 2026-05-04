import {
  commandPaletteDirection,
  scrollSelectedCommandIntoView,
} from "../../lib/global/command_palette";

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

export default CommandPaletteNav;
