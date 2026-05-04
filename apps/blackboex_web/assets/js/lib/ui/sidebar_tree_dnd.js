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

export function destroySortables(sortables) {
  sortables.forEach((sortable) => sortable.destroy());
}
