import { describe, expect, it } from "vitest";
import {
  buildLiveSocket,
  csrfToken,
} from "../../../js/lib/bootstrap/live_socket";

describe("live_socket", () => {
  it("reads the CSRF token from meta tags", () => {
    document.head.innerHTML = '<meta name="csrf-token" content="token-1">';

    expect(csrfToken()).toBe("token-1");
  });

  it("constructs LiveSocket with default Phoenix params and hook map", () => {
    document.head.innerHTML = '<meta name="csrf-token" content="token-2">';
    const hooks = { HookA: {} };
    let captured = null;
    class FakeLiveSocket {
      constructor(path, socket, opts) {
        captured = { path, socket, opts };
      }
    }
    class FakeSocket {}

    const instance = buildLiveSocket(FakeLiveSocket, FakeSocket, hooks);

    expect(instance).toBeInstanceOf(FakeLiveSocket);
    expect(captured.path).toBe("/live");
    expect(captured.socket).toBe(FakeSocket);
    expect(captured.opts.longPollFallbackMs).toBe(2500);
    expect(captured.opts.params).toEqual({ _csrf_token: "token-2" });
    expect(captured.opts.hooks).toBe(hooks);
  });
});
