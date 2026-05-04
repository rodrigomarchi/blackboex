import { describe, expect, it } from "vitest";
import {
  buildNodeHTML,
  countOutputs,
  updateConditionLabel,
  updateOutputLabels,
} from "../../../js/lib/flow/node_catalog";

describe("flow node catalog", () => {
  it("builds branded node HTML with labels and condition controls", () => {
    const html = buildNodeHTML("condition", 2, { name: "Route" });

    expect(html).toContain("Route");
    expect(html).toContain("df-btn-add-output");
    expect(html).toContain("df-branch-count");
  });

  it("falls back for unknown node types", () => {
    expect(buildNodeHTML("custom", 1, {})).toContain("<strong>custom</strong>");
  });

  it("counts outputs through the Drawflow editor API", () => {
    const editor = {
      getNodeFromId: () => ({ outputs: { output_1: {}, output_2: {} } }),
    };

    expect(countOutputs(editor, "1")).toBe(2);
  });

  it("updates branch output labels and branch count", () => {
    document.body.innerHTML = `
      <div id="node-1">
        <div class="df-branch-count">0</div>
        <div class="output"></div>
        <div class="output"><span class="df-output-label">old</span></div>
      </div>
    `;
    const editor = {
      getNodeFromId: () => ({
        class: "condition",
        outputs: { output_1: {}, output_2: {} },
        data: { branch_labels: { 1: "yes" } },
      }),
    };

    updateOutputLabels(editor, "1");
    updateConditionLabel(editor, "1");

    expect(document.querySelectorAll(".df-output-label")[0].textContent).toBe(
      "0",
    );
    expect(document.querySelectorAll(".df-output-label")[1].textContent).toBe(
      "1: yes",
    );
    expect(document.querySelector(".df-branch-count").textContent).toBe("2");
  });
});
