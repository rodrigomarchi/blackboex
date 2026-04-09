/**
 * Converts between Drawflow's internal JSON format and our canonical BlackboexFlow format.
 *
 * BlackboexFlow is the single source of truth — what gets stored in DB, exported, and imported.
 * Drawflow JSON is only used internally by the visual editor.
 *
 * BlackboexFlow format:
 * {
 *   version: "1.0",
 *   nodes: [{ id, type, position: {x, y}, data: {...} }, ...],
 *   edges: [{ id, source, source_port, target, target_port }, ...]
 * }
 */

/**
 * Convert Drawflow export JSON → BlackboexFlow canonical format.
 * Called on save: drawflowToBlackboex(editor.export())
 */
export function drawflowToBlackboex(drawflowData) {
  const nodes = []
  const edges = []

  const homeData = drawflowData?.drawflow?.Home?.data || {}

  for (const [nodeId, node] of Object.entries(homeData)) {
    // Build the BlackboexFlow node
    nodes.push({
      id: `n${nodeId}`,
      type: node.class || "unknown",
      position: { x: node.pos_x || 0, y: node.pos_y || 0 },
      data: node.data || {}
    })

    // Extract edges from this node's outputs
    const outputs = node.outputs || {}
    for (const [outputKey, output] of Object.entries(outputs)) {
      const sourcePort = parseInt(outputKey.replace("output_", ""), 10) - 1
      const connections = output.connections || []

      for (const conn of connections) {
        // Drawflow convention: output connections store {node, output} where
        // "output" is actually the INPUT port name on the target node
        const targetPort = parseInt((conn.output || "input_1").replace("input_", ""), 10) - 1
        // Deterministic edge ID from source/target/ports — stable across round-trips
        const edgeId = `e_n${nodeId}_${sourcePort}_n${conn.node}_${targetPort}`
        edges.push({
          id: edgeId,
          source: `n${nodeId}`,
          source_port: sourcePort,
          target: `n${conn.node}`,
          target_port: targetPort
        })
      }
    }
  }

  return {
    version: "1.0",
    nodes,
    edges
  }
}

/**
 * Convert BlackboexFlow canonical format → Drawflow import JSON.
 * Called on load: editor.import(blackboexToDrawflow(json))
 *
 * @param {object} blackboex - BlackboexFlow JSON
 * @param {function} buildHTML - function(type, outputCount) => HTML string for node rendering
 */
export function blackboexToDrawflow(blackboex, buildHTML) {
  if (!blackboex || !blackboex.nodes) {
    return { drawflow: { Home: { data: {} } } }
  }

  const data = {}

  // Build a map of node edges for counting outputs per node
  const nodeOutputCounts = {}
  for (const node of blackboex.nodes) {
    nodeOutputCounts[node.id] = 0
  }

  // Count max output port per source node from edges
  const nodeOutputMaxPort = {}
  for (const edge of (blackboex.edges || [])) {
    const current = nodeOutputMaxPort[edge.source] || 0
    nodeOutputMaxPort[edge.source] = Math.max(current, edge.source_port + 1)
  }

  // Build connection lookup: source_id -> { output_port -> [{node, output}] }
  // Drawflow convention: in output connections, "output" = the INPUT port on the target
  const connectionMap = {}
  for (const edge of (blackboex.edges || [])) {
    if (!connectionMap[edge.source]) connectionMap[edge.source] = {}
    const outKey = `output_${edge.source_port + 1}`
    if (!connectionMap[edge.source][outKey]) connectionMap[edge.source][outKey] = []

    const targetNodeId = edge.target.replace("n", "")
    const inputKey = `input_${edge.target_port + 1}`
    connectionMap[edge.source][outKey].push({ node: targetNodeId, output: inputKey })
  }

  // Also build reverse connections for inputs
  // Drawflow convention: in input connections, "input" = the OUTPUT port on the source
  const inputConnectionMap = {}
  for (const edge of (blackboex.edges || [])) {
    if (!inputConnectionMap[edge.target]) inputConnectionMap[edge.target] = {}
    const inKey = `input_${edge.target_port + 1}`
    if (!inputConnectionMap[edge.target][inKey]) inputConnectionMap[edge.target][inKey] = []

    const sourceNodeId = edge.source.replace("n", "")
    const outKey = `output_${edge.source_port + 1}`
    inputConnectionMap[edge.target][inKey].push({ node: sourceNodeId, input: outKey })
  }

  for (const node of blackboex.nodes) {
    const numericId = node.id.replace("n", "")

    // Determine input/output count from node type defaults and edges
    let inputCount, outputCount
    switch (node.type) {
      case "start":
        inputCount = 0
        outputCount = Math.max(1, nodeOutputMaxPort[node.id] || 1)
        break
      case "end":
        inputCount = 1
        outputCount = 0
        break
      case "condition":
        inputCount = 1
        outputCount = Math.max(2, nodeOutputMaxPort[node.id] || 2)
        break
      case "http_request":
      case "delay":
      case "sub_flow":
      case "for_each":
      case "webhook_wait":
        inputCount = 1
        outputCount = 1
        break
      default:
        inputCount = 1
        outputCount = Math.max(1, nodeOutputMaxPort[node.id] || 1)
    }

    // Build inputs object
    const inputs = {}
    for (let i = 1; i <= inputCount; i++) {
      const key = `input_${i}`
      const conns = (inputConnectionMap[node.id] && inputConnectionMap[node.id][key]) || []
      inputs[key] = { connections: conns }
    }

    // Build outputs object
    const outputs = {}
    for (let i = 1; i <= outputCount; i++) {
      const key = `output_${i}`
      const conns = (connectionMap[node.id] && connectionMap[node.id][key]) || []
      outputs[key] = { connections: conns }
    }

    const html = buildHTML ? buildHTML(node.type, outputCount, node.data) : `<div>${node.type}</div>`

    data[numericId] = {
      id: parseInt(numericId, 10),
      name: node.type,
      data: node.data || {},
      class: node.type,
      html: html,
      typenode: false,
      inputs: inputs,
      outputs: outputs,
      pos_x: node.position?.x || 0,
      pos_y: node.position?.y || 0
    }
  }

  return {
    drawflow: {
      Home: {
        data: data
      }
    }
  }
}
