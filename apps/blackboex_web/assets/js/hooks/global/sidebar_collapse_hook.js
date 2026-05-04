/**
 * @file Global LiveView hook that restores and persists sidebar collapsed state.
 */
import {
  applySidebarCollapsedState,
  persistSidebarCollapsedState,
} from "../../lib/global/sidebar_collapse";

/**
 * Applies the saved sidebar state on mount and persists changes announced by
 * the component through the `sidebar:toggled` DOM event.
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
 * Sidebar persistence hook registered as `SidebarCollapse`.
 */
export default SidebarCollapse;
