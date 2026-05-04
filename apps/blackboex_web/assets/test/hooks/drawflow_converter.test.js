/**
 * @file Verifies the hook-path compatibility export for flow converters.
 *
 * Ensures imports from `js/hooks/drawflow_converter` still resolve to the same
 * converter functions implemented under `js/lib/flow/drawflow_converter`.
 */
import { describe, expect, it } from "vitest";
import { blackboexToDrawflow } from "../../js/hooks/drawflow_converter";
import { blackboexToDrawflow as libBlackboexToDrawflow } from "../../js/lib/flow/drawflow_converter";

describe("drawflow converter hook shim", () => {
  it("re-exports the flow converter for backwards compatibility", () => {
    expect(blackboexToDrawflow).toBe(libBlackboexToDrawflow);
  });
});
