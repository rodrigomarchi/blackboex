/**
 * @file Global LiveView hook wiring for sidebar collapse hook behavior.
 */
import {
  applySidebarCollapsedState,
  persistSidebarCollapsedState,
} from "../../lib/global/sidebar_collapse";

/**
 * LiveView hook for sidebar collapse behavior.
 */
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

/**
 * Exports the module default value.
 */
export default SidebarCollapse;
