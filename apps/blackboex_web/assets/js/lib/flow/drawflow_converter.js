/**
 * @file Converts between Drawflow's internal graph JSON and the canonical
 * BlackboexFlow definition persisted by the server.
 */
/**
 * @typedef {object} FlowPosition
 * @property {number} x
 * @property {number} y
 *
 * @typedef {object} BlackboexFlowNode
 * @property {string} id
 * @property {string} type
 * @property {FlowPosition} position
 * @property {object} data
 *
 * @typedef {object} BlackboexFlowEdge
 * @property {string} id
 * @property {string} source
 * @property {number} source_port
 * @property {string} target
 * @property {number} target_port
 *
 * @typedef {object} BlackboexFlowDefinition
 * @property {string} version
 * @property {BlackboexFlowNode[]} nodes
 * @property {BlackboexFlowEdge[]} edges
 */
/**
 * Converts Drawflow export data into the canonical BlackboexFlow shape.
 *
 * Drawflow stores node ids as raw numeric strings and edge endpoints inside
 * each node's output connections. BlackboexFlow normalizes those ids with an
 * `n` prefix, stores zero-based source/target ports, and creates deterministic
 * edge ids so repeated save/load cycles do not churn persisted JSON.
 *
 * @param {object} drawflowData - Raw payload returned by `editor.export()`.
 * @returns {BlackboexFlowDefinition} Persistable flow definition.
 */
export function drawflowToBlackboex(drawflowData) {
  const nodes = [];
  const edges = [];

  const homeData = drawflowData?.drawflow?.Home?.data || {};

  for (const [nodeId, node] of Object.entries(homeData)) {
    // Build the BlackboexFlow node
    nodes.push({
      id: `n${nodeId}`,
      type: node.class || "unknown",
      position: { x: node.pos_x || 0, y: node.pos_y || 0 },
      data: node.data || {},
    });

    // Extract edges from this node's outputs
    const outputs = node.outputs || {};
    for (const [outputKey, output] of Object.entries(outputs)) {
      const sourcePort = parseInt(outputKey.replace("output_", ""), 10) - 1;
      const connections = output.connections || [];

      for (const conn of connections) {
        // Drawflow convention: output connections store {node, output} where
        // "output" is actually the INPUT port name on the target node
        const targetPort =
          parseInt((conn.output || "input_1").replace("input_", ""), 10) - 1;
        // Deterministic edge ID from source/target/ports — stable across round-trips
        const edgeId = `e_n${nodeId}_${sourcePort}_n${conn.node}_${targetPort}`;
        edges.push({
          id: edgeId,
          source: `n${nodeId}`,
          source_port: sourcePort,
          target: `n${conn.node}`,
          target_port: targetPort,
        });
      }
    }
  }

  return {
    version: "1.0",
    nodes,
    edges,
  };
}

/**
 * Converts canonical BlackboexFlow JSON into a Drawflow import payload.
 *
 * The converter rebuilds both output-side and input-side connection maps
 * because Drawflow expects mirrored connection data. It also derives each
 * node's input/output counts from node type defaults plus any persisted edges,
 * preserving dynamic condition branches and boundary data-node edges.
 *
 * @param {BlackboexFlowDefinition | null | undefined} blackboex - Persisted flow definition.
 * @param {(type: string, outputCount: number, data?: object) => string} buildHTML - Renderer for Drawflow node HTML.
 * @returns {object} Payload accepted by `editor.import()`.
 */
export function blackboexToDrawflow(blackboex, buildHTML) {
  if (!blackboex || !blackboex.nodes) {
    return { drawflow: { Home: { data: {} } } };
  }

  const data = {};

  // Build a map of node edges for counting outputs per node
  const nodeOutputCounts = {};
  for (const node of blackboex.nodes) {
    nodeOutputCounts[node.id] = 0;
  }

  // Count max output port per source node from edges
  const nodeOutputMaxPort = {};
  for (const edge of blackboex.edges || []) {
    const current = nodeOutputMaxPort[edge.source] || 0;
    nodeOutputMaxPort[edge.source] = Math.max(current, edge.source_port + 1);
  }

  // Build connection lookup: source_id -> { output_port -> [{node, output}] }
  // Drawflow convention: in output connections, "output" = the INPUT port on the target
  const connectionMap = {};
  for (const edge of blackboex.edges || []) {
    if (!connectionMap[edge.source]) connectionMap[edge.source] = {};
    const outKey = `output_${edge.source_port + 1}`;
    if (!connectionMap[edge.source][outKey]) {
      connectionMap[edge.source][outKey] = [];
    }

    const targetNodeId = edge.target.replace("n", "");
    const inputKey = `input_${edge.target_port + 1}`;
    connectionMap[edge.source][outKey].push({
      node: targetNodeId,
      output: inputKey,
    });
  }

  // Also build reverse connections for inputs
  // Drawflow convention: in input connections, "input" = the OUTPUT port on the source
  const inputConnectionMap = {};
  for (const edge of blackboex.edges || []) {
    if (!inputConnectionMap[edge.target]) inputConnectionMap[edge.target] = {};
    const inKey = `input_${edge.target_port + 1}`;
    if (!inputConnectionMap[edge.target][inKey]) {
      inputConnectionMap[edge.target][inKey] = [];
    }

    const sourceNodeId = edge.source.replace("n", "");
    const outKey = `output_${edge.source_port + 1}`;
    inputConnectionMap[edge.target][inKey].push({
      node: sourceNodeId,
      input: outKey,
    });
  }

  for (const node of blackboex.nodes) {
    const numericId = node.id.replace("n", "");

    // Determine input/output count from node type defaults and edges
    let inputCount, outputCount;
    switch (node.type) {
      case "start":
        // Allow input port if an edge targets this start (e.g. boundary input data node)
        inputCount = inputConnectionMap[node.id] ? 1 : 0;
        outputCount = Math.max(1, nodeOutputMaxPort[node.id] || 1);
        break;
      case "end":
        inputCount = 1;
        // Allow output port if an edge leaves this end (e.g. boundary output data node)
        outputCount = nodeOutputMaxPort[node.id] ? 1 : 0;
        break;
      case "condition":
        inputCount = 1;
        outputCount = Math.max(2, nodeOutputMaxPort[node.id] || 2);
        break;
      case "http_request":
      case "delay":
      case "sub_flow":
      case "for_each":
      case "webhook_wait":
        inputCount = 1;
        outputCount = 1;
        break;
      case "fail":
        inputCount = 1;
        outputCount = nodeOutputMaxPort[node.id] ? 1 : 0;
        break;
      default:
        inputCount = 1;
        outputCount = Math.max(1, nodeOutputMaxPort[node.id] || 1);
    }

    // Build inputs object
    const inputs = {};
    for (let i = 1; i <= inputCount; i++) {
      const key = `input_${i}`;
      const conns =
        (inputConnectionMap[node.id] && inputConnectionMap[node.id][key]) || [];
      inputs[key] = { connections: conns };
    }

    // Build outputs object
    const outputs = {};
    for (let i = 1; i <= outputCount; i++) {
      const key = `output_${i}`;
      const conns =
        (connectionMap[node.id] && connectionMap[node.id][key]) || [];
      outputs[key] = { connections: conns };
    }

    const html = buildHTML
      ? buildHTML(node.type, outputCount, node.data)
      : `<div>${node.type}</div>`;

    data[numericId] = {
      id: parseInt(numericId, 10),
      name: node.type,
      data: node.data || {},
      class: node.type === "exec_data" ? "df-exec-data-node" : node.type,
      html: html,
      typenode: false,
      inputs: inputs,
      outputs: outputs,
      pos_x: node.position?.x || 0,
      pos_y: node.position?.y || 0,
    };
  }

  return {
    drawflow: {
      Home: {
        data: data,
      },
    },
  };
}
