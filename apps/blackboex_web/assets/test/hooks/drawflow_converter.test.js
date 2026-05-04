/**
 * @file Vitest coverage for drawflow converter hook behavior.
 */
import { describe, expect, it } from "vitest";
import { blackboexToDrawflow } from "../../js/hooks/drawflow_converter";
import { blackboexToDrawflow as libBlackboexToDrawflow } from "../../js/lib/flow/drawflow_converter";

describe("drawflow converter hook shim", () => {
  it("re-exports the flow converter for backwards compatibility", () => {
    expect(blackboexToDrawflow).toBe(libBlackboexToDrawflow);
  });
});
