/**
 * @file Verifies the Drawflow/BlackboexFlow conversion contract.
 *
 * These tests pin the client-side graph interchange format used by LiveView:
 * Drawflow numeric node ids become stable `n*` ids, port indexes become
 * zero-based edge fields, edge ids are deterministic, and condition nodes
 * imported back into Drawflow keep the minimum branch output shape required by
 * the visual editor.
 */
import {
  blackboexToDrawflow,
  drawflowToBlackboex,
} from "../../../js/lib/flow/drawflow_converter";

describe("drawflow converter", () => {
  it("converts Drawflow export to BlackboexFlow with deterministic edge ids", () => {
    const drawflow = {
      drawflow: {
        Home: {
          data: {
            1: {
              class: "start",
              data: { label: "Start" },
              pos_x: 10,
              pos_y: 20,
              outputs: {
                output_1: { connections: [{ node: "2", output: "input_1" }] },
              },
            },
            2: { class: "end", data: {}, pos_x: 30, pos_y: 40, outputs: {} },
          },
        },
      },
    };

    expect(drawflowToBlackboex(drawflow)).toEqual({
      version: "1.0",
      nodes: [
        {
          id: "n1",
          type: "start",
          position: { x: 10, y: 20 },
          data: { label: "Start" },
        },
        { id: "n2", type: "end", position: { x: 30, y: 40 }, data: {} },
      ],
      edges: [
        {
          id: "e_n1_0_n2_0",
          source: "n1",
          source_port: 0,
          target: "n2",
          target_port: 0,
        },
      ],
    });
  });

  it("converts BlackboexFlow to Drawflow import data", () => {
    const result = blackboexToDrawflow(
      {
        nodes: [
          { id: "n1", type: "condition", position: { x: 1, y: 2 }, data: {} },
        ],
        edges: [],
      },
      (type, outputs) => `${type}:${outputs}`,
    );

    expect(result.drawflow.Home.data["1"].outputs.output_1).toBeDefined();
    expect(result.drawflow.Home.data["1"].outputs.output_2).toBeDefined();
    expect(result.drawflow.Home.data["1"].html).toBe("condition:2");
  });
});
