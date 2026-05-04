import {
  createBubbleMenuEl,
  promptForLink,
} from "../../../js/lib/tiptap/bubble_menu";

describe("bubble menu helpers", () => {
  it("creates action buttons", () => {
    const menu = createBubbleMenuEl(document);
    expect(menu.querySelector("[data-action='bold']")).toBeTruthy();
    expect(menu.querySelector("[data-action='align-left']")).toBeTruthy();
  });

  it("prompts for links and restores selection", () => {
    const run = vi.fn();
    const chain = {
      focus: () => chain,
      setTextSelection: vi.fn(() => chain),
      setLink: vi.fn(() => chain),
      run,
    };
    const editor = {
      isActive: () => false,
      state: { selection: { from: 1, to: 4 } },
      chain: () => chain,
    };

    promptForLink(editor, () => "https://example.com");

    expect(chain.setTextSelection).toHaveBeenCalledWith({ from: 1, to: 4 });
    expect(chain.setLink).toHaveBeenCalledWith({
      href: "https://example.com",
      target: "_blank",
    });
    expect(run).toHaveBeenCalled();
  });
});
