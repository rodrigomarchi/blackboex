import { editorShortcutForEvent } from "../../../js/lib/global/keyboard_shortcuts";

function keyEvent(key, opts = {}) {
  return new KeyboardEvent("keydown", { key, bubbles: true, ...opts });
}

describe("editorShortcutForEvent", () => {
  it("always toggles command palette for Mod+k", () => {
    expect(editorShortcutForEvent(keyEvent("k", { metaKey: true }))).toEqual({
      event: "toggle_command_palette",
      payload: {},
    });
  });

  it("only handles Escape when command palette is open", () => {
    expect(
      editorShortcutForEvent(keyEvent("s", { metaKey: true }), {
        paletteOpen: true,
      }),
    ).toBeNull();
    expect(
      editorShortcutForEvent(keyEvent("Escape"), { paletteOpen: true }),
    ).toEqual({
      event: "toggle_command_palette",
      payload: {},
    });
  });

  it("maps editor shortcuts to LiveView events", () => {
    expect(editorShortcutForEvent(keyEvent("s", { ctrlKey: true })).event).toBe(
      "save",
    );
    expect(editorShortcutForEvent(keyEvent("l", { ctrlKey: true })).event).toBe(
      "toggle_chat",
    );
    expect(editorShortcutForEvent(keyEvent("j", { ctrlKey: true })).event).toBe(
      "toggle_bottom_panel",
    );
    expect(editorShortcutForEvent(keyEvent("i", { ctrlKey: true })).event).toBe(
      "toggle_config",
    );
    expect(
      editorShortcutForEvent(keyEvent("Enter", { ctrlKey: true })).event,
    ).toBe("send_request");
  });

  it("maps Escape to close_panels when palette is closed", () => {
    expect(editorShortcutForEvent(keyEvent("Escape"))).toEqual({
      event: "close_panels",
      payload: {},
    });
  });
});
