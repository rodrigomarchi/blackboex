import Sortable from "../../vendor/sortable.js"

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

const SidebarTreeDnD = {
  mounted() {
    this.sortables = []
    this.initSortables()

    this.handleEvent("sidebar_tree:rollback", () => {
      // The LiveView will have already re-rendered with the correct order;
      // destroy and reinitialise so Sortable picks up the new DOM state.
      this.destroySortables()
      // Wait one animation frame for LiveView morphdom patch to settle
      requestAnimationFrame(() => this.initSortables())
    })
  },

  updated() {
    this.destroySortables()
    this.initSortables()
  },

  destroyed() {
    this.destroySortables()
  },

  initSortables() {
    const lists = this.el.querySelectorAll("[data-tree-list]")
    lists.forEach(list => {
      const s = Sortable.create(list, {
        group: "sidebar-tree",
        delay: 150,
        delayOnTouchOnly: true,
        animation: 120,
        draggable: "[data-tree-item]",
        onEnd: (evt) => {
          const item = evt.item
          const nodeId = item.dataset.nodeId
          const nodeType = item.dataset.nodeType
          const newList = evt.to
          const newParentType = newList.dataset.parentType
          const newParentId = newList.dataset.parentId
          const newIndex = evt.newIndex

          this.pushEventTo(this.el, "move_node", {
            node_id: nodeId,
            node_type: nodeType,
            new_parent_type: newParentType,
            new_parent_id: newParentId,
            new_index: newIndex
          })
        }
      })
      this.sortables.push(s)
    })
  },

  destroySortables() {
    this.sortables.forEach(s => s.destroy())
    this.sortables = []
  }
}

export default SidebarTreeDnD
