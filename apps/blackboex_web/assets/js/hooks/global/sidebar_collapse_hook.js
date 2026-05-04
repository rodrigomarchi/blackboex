import {
  applySidebarCollapsedState,
  persistSidebarCollapsedState,
} from "../../lib/global/sidebar_collapse";

const SidebarCollapse = {
  mounted() {
    applySidebarCollapsedState(this.el, localStorage);
    this.handleToggle = () =>
      persistSidebarCollapsedState(this.el, localStorage);
    this.el.addEventListener("sidebar:toggled", this.handleToggle);
  },

  destroyed() {
    this.el.removeEventListener("sidebar:toggled", this.handleToggle);
  },
};

export default SidebarCollapse;
