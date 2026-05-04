/**
 * @file Verifies the SidebarTreeDnD LiveView hook lifecycle.
 *
 * Covers creating Sortable instances for rendered `data-tree-list` containers
 * and destroying those instances when the hook is torn down.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanupDOM, mountHook } from "../helpers/hook_helper";

vi.mock("../../vendor/sortable.js", () => ({
  default: {
    create: vi.fn(() => ({ destroy: vi.fn() })),
  },
}));

const { default: SidebarTreeDnD } =
  await import("../../js/hooks/sidebar_tree_dnd");

describe("SidebarTreeDnD hook", () => {
  afterEach(() => cleanupDOM());

  it("creates Sortable instances and destroys them on teardown", () => {
    const root = document.createElement("nav");
    root.innerHTML = `
      <ul data-tree-list data-parent-type="project" data-parent-id="p1">
        <li data-tree-item data-node-id="n1" data-node-type="page"></li>
      </ul>
    `;

    const hook = mountHook(SidebarTreeDnD, root);
    const sortable = hook.sortables[0];

    expect(hook.sortables).toHaveLength(1);

    hook.destroyed();

    expect(sortable.destroy).toHaveBeenCalledOnce();
    expect(hook.sortables).toHaveLength(0);
  });
});
