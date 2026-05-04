/**
 * @file Vitest coverage for command palette library helpers.
 */
import {
  commandPaletteDirection,
  findSelectedCommand,
} from "../../../js/lib/global/command_palette";

describe("command palette helpers", () => {
  it("maps arrow keys to directions", () => {
    expect(commandPaletteDirection("ArrowDown")).toBe("down");
    expect(commandPaletteDirection("ArrowUp")).toBe("up");
    expect(commandPaletteDirection("Enter")).toBeNull();
  });

  it("finds the selected command item", () => {
    document.body.innerHTML =
      '<div id="command-palette-list"><div></div><div class="bg-base-200"></div></div>';
    expect(findSelectedCommand(document).className).toBe("bg-base-200");
  });
});
