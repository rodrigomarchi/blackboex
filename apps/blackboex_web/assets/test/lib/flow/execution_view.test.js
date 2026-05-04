import { describe, expect, it } from "vitest";
import {
  applyExecutionHighlights,
  buildExecutionDataNodeHtml,
  formatExecutionDuration,
} from "../../../js/lib/flow/execution_view";

describe("execution_view", () => {
  it("formats execution durations", () => {
    expect(formatExecutionDuration(null)).toBe("");
    expect(formatExecutionDuration(900)).toBe("900ms");
    expect(formatExecutionDuration(1250)).toBe("1.3s");
  });

  it("encodes JSON output in data node HTML", () => {
    const html = buildExecutionDataNodeHtml(
      { status: "completed", output: { ok: true } },
      "n1",
    );

    expect(html).toContain("df-exec-dn-cm");
    expect(html).toContain('data-exec-key="n1"');
    expect(html).toContain("data-b64");
  });

  it("applies status highlights to original nodes", () => {
    document.body.innerHTML = '<div id="node-1"></div>';

    applyExecutionHighlights([
      { id: "n1", status: "completed", duration_ms: 50 },
    ]);

    expect(
      document.getElementById("node-1").classList.contains("df-exec-highlight"),
    ).toBe(true);
    expect(
      document.querySelector(".df-exec-status-pill").textContent,
    ).toContain("completed");
  });
});
