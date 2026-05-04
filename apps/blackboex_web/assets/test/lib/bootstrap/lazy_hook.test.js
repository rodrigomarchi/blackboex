import { describe, expect, it, vi } from "vitest";
import { lazyHook } from "../../../js/lib/bootstrap/lazy_hook";
import { mountHook } from "../../helpers/hook_helper";

describe("lazyHook", () => {
  it("loads the real hook and forwards LiveView lifecycle calls", async () => {
    const realHook = {
      mounted: vi.fn(),
      updated: vi.fn(),
      destroyed: vi.fn(),
    };
    const loader = vi.fn(async () => ({ default: realHook }));
    const hook = mountHook(lazyHook(loader));

    hook.updated();
    await hook.__lazyHook.promise;
    hook.destroyed();

    expect(loader).toHaveBeenCalledOnce();
    expect(realHook.mounted).toHaveBeenCalledOnce();
    expect(realHook.updated).toHaveBeenCalledOnce();
    expect(realHook.destroyed).toHaveBeenCalledOnce();
  });

  it("does not mount the real hook if destroyed before import resolves", async () => {
    const realHook = { mounted: vi.fn() };
    let resolveLoader;
    const loader = vi.fn(
      () =>
        new Promise((resolve) => {
          resolveLoader = resolve;
        }),
    );
    const hook = mountHook(lazyHook(loader));

    hook.destroyed();
    resolveLoader({ default: realHook });
    await hook.__lazyHook.promise;

    expect(realHook.mounted).not.toHaveBeenCalled();
  });
});
