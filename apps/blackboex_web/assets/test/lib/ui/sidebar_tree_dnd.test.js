import { buildMoveNodePayload } from "../../../js/lib/ui/sidebar_tree_dnd";

describe("sidebar tree dnd helpers", () => {
  it("builds move_node payload from Sortable event", () => {
    const item = document.createElement("li");
    item.dataset.nodeId = "api-1";
    item.dataset.nodeType = "api";
    const list = document.createElement("ul");
    list.dataset.parentType = "project";
    list.dataset.parentId = "project-1";

    expect(buildMoveNodePayload({ item, to: list, newIndex: 2 })).toEqual({
      node_id: "api-1",
      node_type: "api",
      new_parent_type: "project",
      new_parent_id: "project-1",
      new_index: 2,
    });
  });
});
