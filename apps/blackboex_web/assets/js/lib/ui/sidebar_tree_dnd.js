/**
 * @file Shared JavaScript library helpers for ui behavior.
 */
/**
 * Provides build move node payload.
 * @param {unknown} evt - evt value.
 * @returns {unknown} Function result.
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
 * Provides create sortables.
 * @param {unknown} root - Root element or document used for lookup.
 * @param {unknown} Sortable - Sortable value.
 * @param {unknown} onMoveNode - onMoveNode value.
 * @returns {unknown} Function result.
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
 * Provides destroy sortables.
 * @param {unknown} sortables - sortables value.
 * @returns {unknown} Function result.
 */
export function destroySortables(sortables) {
  sortables.forEach((sortable) => sortable.destroy());
}
