/**
 * @file Sortable.js helpers for moving nested sidebar tree nodes in LiveView.
 */
/**
 * Converts a Sortable drop event into the payload expected by the sidebar LiveView.
 * @param {{item: HTMLElement, to: HTMLElement, newIndex: number}} evt - Sortable onEnd event.
 * @returns {{node_id: string | undefined, node_type: string | undefined, new_parent_type: string | undefined, new_parent_id: string | undefined, new_index: number}} LiveView move payload.
 */
export function buildMoveNodePayload(evt) {
  const item = evt.item;
  const newList = evt.to;

  return {
    node_id: item.dataset.nodeId,
    node_type: item.dataset.nodeType,
    new_parent_type: newList.dataset.parentType,
    new_parent_id: newList.dataset.parentId,
    new_index: evt.newIndex,
  };
}

/**
 * Attaches Sortable instances to every tree list inside a sidebar hook root.
 * @param {ParentNode} root - Hook root that contains `[data-tree-list]` containers.
 * @param {{create: Function}} Sortable - Sortable.js constructor namespace.
 * @param {Function} onMoveNode - Callback that receives the normalized LiveView payload.
 * @returns {Array<{destroy: Function}>} Sortable instances that must be destroyed with the hook.
 */
export function createSortables(root, Sortable, onMoveNode) {
  const sortables = [];
  root.querySelectorAll("[data-tree-list]").forEach((list) => {
    const sortable = Sortable.create(list, {
      group: "sidebar-tree",
      delay: 150,
      delayOnTouchOnly: true,
      animation: 120,
      draggable: "[data-tree-item]",
      onEnd: (evt) => onMoveNode(buildMoveNodePayload(evt)),
    });
    sortables.push(sortable);
  });
  return sortables;
}

/**
 * Tears down all Sortable instances owned by the sidebar hook.
 * @param {Array<{destroy: Function}>} sortables - Instances returned by `createSortables`.
 * @returns {void}
 */
export function destroySortables(sortables) {
  sortables.forEach((sortable) => sortable.destroy());
}
