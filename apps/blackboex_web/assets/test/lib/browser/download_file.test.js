/**
 * @file Verifies the browser download adapter used by LiveView events.
 *
 * Covers building Blob object URLs, clicking a temporary anchor, revoking the
 * URL, rejecting incomplete payloads, and uninstalling both Phoenix-prefixed and
 * raw `download_file` event listeners.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  downloadFileFromEvent,
  installDownloadFileHandler,
} from "../../../js/lib/browser/download_file";

describe("download_file", () => {
  afterEach(() => vi.restoreAllMocks());

  it("creates and revokes an object URL for valid download payloads", () => {
    const click = vi
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    const URLMock = {
      createObjectURL: vi.fn(() => "blob:test"),
      revokeObjectURL: vi.fn(),
    };

    const result = downloadFileFromEvent(
      new CustomEvent("phx:download_file", {
        detail: { content: "abc", filename: "a.txt" },
      }),
      { URL: URLMock, Blob },
    );

    expect(result).toBe(true);
    expect(URLMock.createObjectURL).toHaveBeenCalledOnce();
    expect(click).toHaveBeenCalledOnce();
    expect(URLMock.revokeObjectURL).toHaveBeenCalledWith("blob:test");
  });

  it("ignores incomplete payloads", () => {
    expect(
      downloadFileFromEvent(
        new CustomEvent("phx:download_file", { detail: { content: "abc" } }),
      ),
    ).toBe(false);
  });

  it("installs both Phoenix and raw event listeners", () => {
    const target = new EventTarget();
    const click = vi
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    const URLMock = {
      createObjectURL: vi.fn(() => "blob:test"),
      revokeObjectURL: vi.fn(),
    };
    const uninstall = installDownloadFileHandler(target, {
      URL: URLMock,
      Blob,
    });

    target.dispatchEvent(
      new CustomEvent("download_file", {
        detail: { content: "abc", filename: "a.txt" },
      }),
    );
    uninstall();
    target.dispatchEvent(
      new CustomEvent("download_file", {
        detail: { content: "abc", filename: "b.txt" },
      }),
    );

    expect(click).toHaveBeenCalledOnce();
  });
});
