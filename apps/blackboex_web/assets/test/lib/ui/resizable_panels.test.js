import {
  applyPanelSize,
  clampPanelSize,
  loadPanelSizes,
  panelSizeProperty,
  savePanelSizes,
} from "../../../js/lib/ui/resizable_panels";

describe("resizable panel helpers", () => {
  it("clamps vertical and horizontal sizes", () => {
    expect(clampPanelSize("vertical", 50)).toBe(100);
    expect(clampPanelSize("vertical", 700)).toBe(600);
    expect(clampPanelSize("horizontal", 100)).toBe(200);
    expect(clampPanelSize("horizontal", 600)).toBe(500);
  });

  it("selects the correct CSS property", () => {
    expect(panelSizeProperty("vertical")).toBe("height");
    expect(panelSizeProperty("horizontal")).toBe("width");
  });

  it("applies size to inline style or CSS variable", () => {
    const target = document.createElement("div");
    applyPanelSize({ target, direction: "vertical" }, 220);
    expect(target.style.height).toBe("220px");

    applyPanelSize(
      { target, cssVar: "--pane-size", direction: "horizontal" },
      330,
      document.documentElement,
    );
    expect(document.documentElement.style.getPropertyValue("--pane-size")).toBe(
      "330px",
    );
  });

  it("persists and loads panel sizes", () => {
    const storage = { setItem: vi.fn(), getItem: vi.fn(() => '{"panel":250}') };
    savePanelSizes(
      [
        {
          state: {
            target: { id: "panel", offsetHeight: 250 },
            direction: "vertical",
          },
        },
      ],
      storage,
    );
    expect(storage.setItem).toHaveBeenCalled();
    expect(loadPanelSizes(storage)).toEqual({ panel: 250 });
  });
});
