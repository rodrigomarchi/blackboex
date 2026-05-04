/**
 * @file Vitest coverage for clipboard library helpers.
 */
import { copyTextFromEvent } from "../../../js/lib/browser/clipboard";

describe("clipboard adapter", () => {
  it("copies text from phx event detail", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    const event = new CustomEvent("phx:copy_to_clipboard", {
      detail: { text: "hello" },
    });

    await copyTextFromEvent(event, { clipboard: { writeText } });

    expect(writeText).toHaveBeenCalledWith("hello");
  });

  it("ignores missing text", async () => {
    const writeText = vi.fn();
    await copyTextFromEvent(new CustomEvent("x", { detail: {} }), {
      clipboard: { writeText },
    });
    expect(writeText).not.toHaveBeenCalled();
  });
});
