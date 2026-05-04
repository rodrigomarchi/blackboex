import { describe, expect, it, vi } from "vitest";
import { elixirCompletionSource } from "../../js/lib/elixir_completion";

function contextFor(text, from = 0) {
  return {
    matchBefore: () => ({ text, from, to: from + text.length }),
  };
}

describe("elixirCompletionSource", () => {
  it("does not query the server below the completion threshold", async () => {
    const hook = { pushEvent: vi.fn() };
    const source = elixirCompletionSource(hook);

    expect(await source(contextFor("E"))).toBeNull();
    expect(hook.pushEvent).not.toHaveBeenCalled();
  });

  it("strips arity for insertion and replaces only the segment after a dot", async () => {
    const hook = {
      pushEvent: vi.fn((_event, _payload, reply) => {
        reply({
          items: [{ label: "map/2", type: "function", detail: "Enum.map/2" }],
        });
      }),
    };
    const source = elixirCompletionSource(hook);

    const result = await source(contextFor("Enum.ma", 10));

    expect(hook.pushEvent).toHaveBeenCalledWith(
      "autocomplete",
      { hint: "Enum.ma" },
      expect.any(Function),
    );
    expect(result.from).toBe(15);
    expect(result.options[0]).toMatchObject({
      label: "map/2",
      type: "function",
      apply: "map",
    });
  });

  it("falls back to null when the server does not reply before timeout", async () => {
    vi.useFakeTimers();
    const hook = { pushEvent: vi.fn() };
    const source = elixirCompletionSource(hook);
    const promise = source(contextFor("Enum.ma"));

    vi.advanceTimersByTime(2000);
    await expect(promise).resolves.toBeNull();
    vi.useRealTimers();
  });
});
