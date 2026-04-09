import Drawflow from "../../vendor/drawflow.min.js"
import { drawflowToBlackboex, blackboexToDrawflow } from "./drawflow_converter.js"

// Node type visual config
const nodeConfig = {
  start: {
    color: "#10b981",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path d="M6.3 2.84A1.5 1.5 0 0 0 4 4.11v11.78a1.5 1.5 0 0 0 2.3 1.27l9.344-5.891a1.5 1.5 0 0 0 0-2.538L6.3 2.841Z" /></svg>`,
    label: "Start",
    subtitle: "Trigger"
  },
  elixir_code: {
    color: "#8b5cf6",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M6.28 5.22a.75.75 0 0 1 0 1.06L2.56 10l3.72 3.72a.75.75 0 0 1-1.06 1.06L.97 10.53a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Zm7.44 0a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L17.44 10l-3.72-3.72a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" /></svg>`,
    label: "Elixir Code",
    subtitle: "Run Elixir code"
  },
  condition: {
    color: "#3b82f6",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M10 3a.75.75 0 0 1 .55.24l3.25 3.5a.75.75 0 1 1-1.1 1.02L10 4.852 7.3 7.76a.75.75 0 0 1-1.1-1.02l3.25-3.5A.75.75 0 0 1 10 3Zm-3.76 9.2a.75.75 0 0 1 1.06.04l2.7 2.908 2.7-2.908a.75.75 0 1 1 1.1 1.02l-3.25 3.5a.75.75 0 0 1-1.1 0l-3.25-3.5a.75.75 0 0 1 .04-1.06Z" clip-rule="evenodd" /></svg>`,
    label: "Condition",
    subtitle: "Branch"
  },
  end: {
    color: "#6b7280",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M2 10a8 8 0 1 1 16 0 8 8 0 0 1-16 0Zm5-2.25A.75.75 0 0 1 7.75 7h.5a.75.75 0 0 1 .75.75v4.5a.75.75 0 0 1-.75.75h-.5a.75.75 0 0 1-.75-.75v-4.5Zm4 0a.75.75 0 0 1 .75-.75h.5a.75.75 0 0 1 .75.75v4.5a.75.75 0 0 1-.75.75h-.5a.75.75 0 0 1-.75-.75v-4.5Z" clip-rule="evenodd" /></svg>`,
    label: "End",
    subtitle: "Stop flow"
  },
  http_request: {
    color: "#f97316",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM4.332 8.027a6.012 6.012 0 0 1 1.912-2.706C6.512 5.73 6.974 6 7.5 6A1.5 1.5 0 0 1 9 7.5V8a2 2 0 0 0 4 0 2 2 0 0 1 1.523-1.943A5.977 5.977 0 0 1 16 10c0 .34-.028.675-.083 1H15a2 2 0 0 0-2 2v2.197A5.973 5.973 0 0 1 10 16v-2a2 2 0 0 0-2-2 2 2 0 0 1-2-2 2 2 0 0 0-1.668-1.973Z" clip-rule="evenodd" /></svg>`,
    label: "HTTP Request",
    subtitle: "Call API"
  },
  delay: {
    color: "#eab308",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm.75-13a.75.75 0 0 0-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 0 0 0-1.5h-3.25V5Z" clip-rule="evenodd" /></svg>`,
    label: "Delay",
    subtitle: "Wait"
  },
  sub_flow: {
    color: "#6366f1",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path d="M2 4.5A2.5 2.5 0 0 1 4.5 2h3A2.5 2.5 0 0 1 10 4.5v3A2.5 2.5 0 0 1 7.5 10h-3A2.5 2.5 0 0 1 2 7.5v-3ZM2 12.5A2.5 2.5 0 0 1 4.5 10h3a2.5 2.5 0 0 1 2.5 2.5v3A2.5 2.5 0 0 1 7.5 18h-3A2.5 2.5 0 0 1 2 15.5v-3ZM10 4.5A2.5 2.5 0 0 1 12.5 2h3A2.5 2.5 0 0 1 18 4.5v3a2.5 2.5 0 0 1-2.5 2.5h-3A2.5 2.5 0 0 1 10 7.5v-3Z" /></svg>`,
    label: "Sub-Flow",
    subtitle: "Nested flow"
  },
  for_each: {
    color: "#14b8a6",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path d="M15.312 11.424a5.5 5.5 0 0 1-9.201 2.466l-.312-.311h2.433a.75.75 0 0 0 0-1.5H4.233a.75.75 0 0 0-.75.75v4a.75.75 0 0 0 1.5 0v-2.146l.312.31a7 7 0 0 0 11.712-3.138.75.75 0 0 0-1.449-.39Zm1.455-7.191a.75.75 0 0 0-1.5 0v2.146l-.312-.31a7 7 0 0 0-11.712 3.138.75.75 0 0 0 1.449.39 5.5 5.5 0 0 1 9.201-2.466l.312.311h-2.433a.75.75 0 0 0 0 1.5H15.767a.75.75 0 0 0 .75-.75v-4Z" /></svg>`,
    label: "For Each",
    subtitle: "Iterate list"
  },
  webhook_wait: {
    color: "#ec4899",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path d="M3.196 12.87l-.825.483a.75.75 0 0 0 .762 1.294l.825-.484a3.978 3.978 0 0 0 2.08 1.088l-.076.95a.75.75 0 1 0 1.496.12l.076-.95c.796-.087 1.524-.4 2.11-.878l.669.614a.75.75 0 0 0 1.016-1.105l-.669-.613a4.001 4.001 0 0 0 .95-2.187h.87a.75.75 0 0 0 0-1.5h-.87a4.002 4.002 0 0 0-.95-2.187l.669-.613A.75.75 0 0 0 10.68 5.99l-.669.613a3.98 3.98 0 0 0-2.11-.878l-.076-.95A.75.75 0 1 0 6.33 4.894l.076.95a3.978 3.978 0 0 0-2.08 1.088l-.825-.484a.75.75 0 0 0-.762 1.294l.825.484A3.987 3.987 0 0 0 3 10c0 1.073.421 2.048 1.108 2.766L3.196 12.87Z" /></svg>`,
    label: "Webhook Wait",
    subtitle: "Pause for event"
  }
}

function countOutputs(editor, nodeId) {
  const node = editor.getNodeFromId(nodeId)
  return node ? Object.keys(node.outputs).length : 0
}

export function buildNodeHTML(type, outputs, data) {
  const cfg = nodeConfig[type]
  if (!cfg) return `<div class="df-node"><strong>${type}</strong></div>`

  const name = (data && data.name) || cfg.label

  const controls = type === "condition"
    ? `<div class="df-node-controls">
        <button class="df-btn df-btn-remove-output" title="Remove branch">−</button>
        <span class="df-branch-count">${outputs}</span>
        <button class="df-btn df-btn-add-output" title="Add branch">+</button>
      </div>`
    : ""

  return `<div class="df-node" style="--node-color: ${cfg.color}">
    <div class="df-node-header">
      <div class="df-node-icon-wrap" style="background: ${cfg.color}15; color: ${cfg.color}">
        ${cfg.icon}
      </div>
      <div class="df-node-text">
        <div class="df-node-label">${name}</div>
      </div>
    </div>
    ${controls}
  </div>`
}

function updateOutputLabels(editor, nodeId) {
  const node = editor.getNodeFromId(nodeId)
  if (!node || node.class !== "condition") return

  const el = document.querySelector(`#node-${nodeId}`)
  if (!el) return

  const branchLabels = (node.data && node.data.branch_labels) || {}
  const outputs = el.querySelectorAll(".output")

  outputs.forEach((output, index) => {
    // Remove existing label if any
    const existing = output.querySelector(".df-output-label")
    if (existing) existing.remove()

    const label = branchLabels[String(index)]
    const text = label ? `${index}: ${label}` : String(index)

    const labelEl = document.createElement("span")
    labelEl.className = "df-output-label"
    labelEl.textContent = text
    output.appendChild(labelEl)
  })
}

function updateAllOutputLabels(editor) {
  const data = editor.export()
  const homeModule = data.drawflow?.Home?.data
  if (!homeModule) return
  for (const nodeId of Object.keys(homeModule)) {
    updateOutputLabels(editor, nodeId)
  }
}

function updateConditionLabel(editor, nodeId) {
  const count = countOutputs(editor, nodeId)
  const el = document.querySelector(`#node-${nodeId}`)
  if (!el) return

  const subtitle = el.querySelector(".df-node-subtitle")
  if (subtitle) subtitle.textContent = `${count} branches`

  const badge = el.querySelector(".df-branch-count")
  if (badge) badge.textContent = count
}

const DrawflowEditor = {
  mounted() {
    this.editor = new Drawflow(this.el)
    this.editor.reroute = true
    this.editor.curvature = 0.5
    this.editor.reroute_curvature_start_end = 0.5
    this.editor.reroute_curvature = 0.5
    this.editor.start()

    // Load existing definition (BlackboexFlow format from server)
    const definition = this.el.dataset.definition
    if (definition) {
      try {
        const parsed = JSON.parse(definition)
        if (parsed && parsed.version && parsed.nodes) {
          // Convert BlackboexFlow → Drawflow for the editor
          const drawflowData = blackboexToDrawflow(parsed, buildNodeHTML)
          this.editor.import(drawflowData)
        } else if (parsed && parsed.drawflow) {
          // Legacy: raw Drawflow JSON (backwards compat during migration)
          this.editor.import(parsed)
        }
      } catch (_e) {
        // Empty or invalid definition — start fresh
      }
    }

    // Render output labels on condition nodes after import
    setTimeout(() => updateAllOutputLabels(this.editor), 100)

    // ── Node selection → push to LiveView for properties drawer ──
    this.editor.on("nodeSelected", (nodeId) => {
      const node = this.editor.getNodeFromId(nodeId)
      if (node) {
        this.pushEvent("node_selected", {
          id: String(nodeId),
          type: node.class,
          data: node.data || {}
        })
      }
    })

    this.editor.on("nodeUnselected", () => {
      this.pushEvent("node_deselected", {})
    })

    // When a node is removed, close the drawer
    this.editor.on("nodeRemoved", () => {
      this.pushEvent("node_deselected", {})
    })

    // Also close drawer when clicking empty canvas
    this.editor.on("click", () => {
      // Drawflow fires nodeUnselected separately, but this catches edge cases
    })

    // ── Server pushes updated data back to a node ──
    this.handleEvent("set_node_data", ({ id, data }) => {
      const node = this.editor.getNodeFromId(id)
      if (node) {
        // Merge data into node
        node.data = { ...node.data, ...data }

        // Update the node label when name changes
        const cfg = nodeConfig[node.class] || {}
        const labelEl = document.querySelector(`#node-${id} .df-node-label`)
        if (labelEl) labelEl.textContent = node.data.name || cfg.label || node.class

        // Update output labels if branch_labels changed
        if (data.branch_labels) {
          updateOutputLabels(this.editor, id)
        }
      }
    })

    // ── Condition node +/- buttons ──
    this.el.addEventListener("click", (e) => {
      const addBtn = e.target.closest(".df-btn-add-output")
      const removeBtn = e.target.closest(".df-btn-remove-output")

      if (addBtn || removeBtn) {
        e.stopPropagation()
        const nodeEl = e.target.closest(".drawflow-node")
        if (!nodeEl) return
        const nodeId = nodeEl.id.replace("node-", "")

        if (addBtn) {
          this.editor.addNodeOutput(nodeId)
          updateConditionLabel(this.editor, nodeId)
          updateOutputLabels(this.editor, nodeId)
        }

        if (removeBtn) {
          const outputs = countOutputs(this.editor, nodeId)
          if (outputs > 1) {
            this.editor.removeNodeOutput(nodeId, `output_${outputs}`)
            updateConditionLabel(this.editor, nodeId)
            updateOutputLabels(this.editor, nodeId)
          }
        }
      }
    })

    // ── Drag-drop from sidebar ──
    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      const type = e.dataTransfer.getData("node-type")
      const inputs = parseInt(e.dataTransfer.getData("node-inputs") || "1")
      const outputs = parseInt(e.dataTransfer.getData("node-outputs") || "1")

      if (type) {
        const html = buildNodeHTML(type, outputs, {})
        const rect = this.el.getBoundingClientRect()
        const x = (e.clientX - rect.left - this.editor.precanvas.getBoundingClientRect().left + this.editor.canvas_x) / this.editor.zoom
        const y = (e.clientY - rect.top - this.editor.precanvas.getBoundingClientRect().top + this.editor.canvas_y) / this.editor.zoom

        this.editor.addNode(type, inputs, outputs, x, y, type, {}, html)
      }
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
    })

    // Set up drag data on sidebar items
    document.querySelectorAll("[data-node-type]").forEach((el) => {
      el.addEventListener("dragstart", (e) => {
        e.dataTransfer.setData("node-type", el.dataset.nodeType)
        e.dataTransfer.setData("node-label", el.dataset.nodeLabel)
        e.dataTransfer.setData("node-inputs", el.dataset.nodeInputs)
        e.dataTransfer.setData("node-outputs", el.dataset.nodeOutputs)
      })
    })

    // ── Save/load events ──
    this.handleEvent("export_definition", () => {
      const drawflowData = this.editor.export()
      const blackboexData = drawflowToBlackboex(drawflowData)
      this.pushEvent("save_definition", { definition: blackboexData })
    })

    this.handleEvent("definition_saved", () => {})

    // JSON preview modal — show BlackboexFlow format
    this.handleEvent("export_json_preview", () => {
      const drawflowData = this.editor.export()
      const blackboexData = drawflowToBlackboex(drawflowData)
      this.pushEvent("show_json_preview", { definition: blackboexData })
    })
  },

  destroyed() {
    if (this.editor) {
      this.editor.clear()
    }
  }
}

export default DrawflowEditor
