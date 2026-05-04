/**
 * @file LiveView hook wiring for sidebar tree dnd behavior.
 */
import Sortable from "../../vendor/sortable.js";
import {
  buildMoveNodePayload,
  createSortables,
  destroySortables,
} from "../lib/ui/sidebar_tree_dnd";

// SidebarTreeDnD — enables drag-and-drop reordering and reparenting within the
// sidebar navigation tree. Mounts one Sortable instance per `[data-tree-list]`
// element found inside the hook root, with cross-list drag enabled via a shared
// group name.
//
// DOM contract (set by sidebar_tree_component.ex):
//   Hook root:  phx-hook="SidebarTreeDnD" on the <nav> element
//   Each list:  data-tree-list data-parent-type="{type}" data-parent-id="{id}"
//   Each item:  data-tree-item data-node-id="{id}" data-node-type="{type}"
//
// Server event pushed: "move_node" with payload:
//   node_id, node_type, new_parent_type, new_parent_id, new_index
//
// Server event handled: "sidebar_tree:rollback" — re-initialises Sortable to
//   snap the UI back to the server-authoritative state on a rejected move.

/**
 * LiveView hook for sidebar tree dn d behavior.
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
 * Exports the module default value.
 */
export default SidebarTreeDnD;
export { buildMoveNodePayload };
