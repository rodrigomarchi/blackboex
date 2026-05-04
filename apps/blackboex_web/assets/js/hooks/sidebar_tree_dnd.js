/**
 * @file LiveView hook for sidebar tree drag, reorder, and reparent operations.
 */
import Sortable from "../../vendor/sortable.js";
import {
  buildMoveNodePayload,
  createSortables,
  destroySortables,
} from "../lib/ui/sidebar_tree_dnd";

/**
 * Sortable-backed hook for sidebar navigation trees.
 *
 * The server renders tree lists with `data-parent-*` and items with
 * `data-node-*`. On drop the hook pushes `move_node` to the hook target, and on
 * `sidebar_tree:rollback` it reinitializes Sortable after LiveView restores the
 * server-authoritative order.
 */
const SidebarTreeDnD = {
  mounted() {
    this.sortables = [];
    this.initSortables();

    this.handleEvent("sidebar_tree:rollback", () => {
      // The LiveView will have already re-rendered with the correct order;
      // destroy and reinitialise so Sortable picks up the new DOM state.
      this.destroySortables();
      // Wait one animation frame for LiveView morphdom patch to settle
      requestAnimationFrame(() => this.initSortables());
    });
  },

  updated() {
    this.destroySortables();
    this.initSortables();
  },

  destroyed() {
    this.destroySortables();
  },

  initSortables() {
    this.sortables = createSortables(this.el, Sortable, (payload) => {
      this.pushEventTo(this.el, "move_node", payload);
    });
  },

  destroySortables() {
    destroySortables(this.sortables);
    this.sortables = [];
  },
};

/**
 * Sidebar tree drag-and-drop hook registered as `SidebarTreeDnD`.
 */
export default SidebarTreeDnD;
export { buildMoveNodePayload };
