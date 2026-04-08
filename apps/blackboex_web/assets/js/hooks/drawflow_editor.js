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
  }
}

function countOutputs(editor, nodeId) {
  const node = editor.getNodeFromId(nodeId)
  return node ? Object.keys(node.outputs).length : 0
}

export function buildNodeHTML(type, outputs) {
  const cfg = nodeConfig[type]
  if (!cfg) return `<div class="df-node"><strong>${type}</strong></div>`

  const subtitle = type === "condition" ? `${outputs} branches` : cfg.subtitle

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
        <div class="df-node-label">${cfg.label}</div>
        <div class="df-node-subtitle">${subtitle}</div>
      </div>
    </div>
    ${controls}
  </div>`
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

        // Update the node label if name was changed
        if (data.name) {
          const el = document.querySelector(`#node-${id} .df-node-label`)
          if (el) el.textContent = data.name
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
        }

        if (removeBtn) {
          const outputs = countOutputs(this.editor, nodeId)
          if (outputs > 1) {
            this.editor.removeNodeOutput(nodeId, `output_${outputs}`)
            updateConditionLabel(this.editor, nodeId)
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
        const html = buildNodeHTML(type, outputs)
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
