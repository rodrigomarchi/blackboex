import Drawflow from "../../vendor/drawflow.min.js"
import dagre from "../../vendor/dagre.min.js"
import { drawflowToBlackboex, blackboexToDrawflow } from "./drawflow_converter.js"
import { EditorState } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import { buildExtensions } from "../lib/codemirror_setup"

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
  },
  fail: {
    color: "#ef4444",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM8.28 7.22a.75.75 0 0 0-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 1 0 1.06 1.06L10 11.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L11.06 10l1.72-1.72a.75.75 0 0 0-1.06-1.06L10 8.94 8.28 7.22Z" clip-rule="evenodd" /></svg>`,
    label: "Fail",
    subtitle: "Error exit"
  },
  debug: {
    color: "#a855f7",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M4.5 2A2.5 2.5 0 0 0 2 4.5v3.879a2.5 2.5 0 0 0 .732 1.767l7.5 7.5a2.5 2.5 0 0 0 3.536 0l3.878-3.878a2.5 2.5 0 0 0 0-3.536l-7.5-7.5A2.5 2.5 0 0 0 8.38 2H4.5ZM5 6a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd" /></svg>`,
    label: "Debug",
    subtitle: "Inspect data"
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


// Fit canvas so all nodes are visible with padding
function fitView(editor) {
  const data = editor.export()
  const homeData = data.drawflow?.Home?.data
  if (!homeData || Object.keys(homeData).length === 0) return

  const nodes = Object.values(homeData)
  const padding = 80

  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  nodes.forEach(n => {
    const el = document.querySelector(`#node-${n.id}`)
    const w = el ? el.offsetWidth : 200
    const h = el ? el.offsetHeight : 80
    if (n.pos_x < minX) minX = n.pos_x
    if (n.pos_y < minY) minY = n.pos_y
    if (n.pos_x + w > maxX) maxX = n.pos_x + w
    if (n.pos_y + h > maxY) maxY = n.pos_y + h
  })

  const graphW = maxX - minX + padding * 2
  const graphH = maxY - minY + padding * 2
  const container = editor.container
  const containerW = container.clientWidth
  const containerH = container.clientHeight

  const scaleX = containerW / graphW
  const scaleY = containerH / graphH
  const scale = Math.min(scaleX, scaleY, editor.zoom_max)
  const clampedScale = Math.max(scale, editor.zoom_min)

  editor.zoom = clampedScale
  editor.canvas_x = -(minX - padding) * clampedScale + (containerW - graphW * clampedScale) / 2
  editor.canvas_y = -(minY - padding) * clampedScale + (containerH - graphH * clampedScale) / 2

  const precanvas = editor.precanvas
  precanvas.style.transform = `translate(${editor.canvas_x}px, ${editor.canvas_y}px) scale(${clampedScale})`
  editor.dispatch("zoom", clampedScale)
}

// Auto-layout using dagre (left-to-right hierarchy)
function autoLayout(editor, opts = {}) {
  const data = editor.export()
  const homeData = data.drawflow?.Home?.data
  if (!homeData || Object.keys(homeData).length === 0) return

  const nodesep = opts.nodesep || 60
  const ranksep = opts.ranksep || 120

  const g = new dagre.graphlib.Graph()
  g.setGraph({ rankdir: "LR", nodesep, ranksep, marginx: 80, marginy: 80 })
  g.setDefaultEdgeLabel(() => ({}))

  // Add nodes with measured dimensions
  Object.entries(homeData).forEach(([id, node]) => {
    const el = document.querySelector(`#node-${id}`)
    const w = el ? el.offsetWidth : 200
    const h = el ? el.offsetHeight : 80
    g.setNode(id, { width: w + 20, height: h + 20 })
  })

  // Add edges from connections
  Object.entries(homeData).forEach(([id, node]) => {
    Object.values(node.outputs || {}).forEach(output => {
      output.connections.forEach(conn => {
        g.setEdge(id, conn.node)
      })
    })
  })

  dagre.layout(g)

  // Apply positions — dagre gives center coords, drawflow uses top-left
  g.nodes().forEach(nodeId => {
    const layoutNode = g.node(nodeId)
    const dfNode = homeData[nodeId]
    if (dfNode && layoutNode) {
      dfNode.pos_x = layoutNode.x - layoutNode.width / 2
      dfNode.pos_y = layoutNode.y - layoutNode.height / 2
    }
  })

  editor.clear()
  editor.import(data)

  // Re-render condition branch labels after import
  setTimeout(() => updateAllOutputLabels(editor), 100)
}

function updateZoomLabel(editor, toolbar) {
  const label = toolbar.querySelector("[data-zoom-label]")
  if (label) label.textContent = `${Math.round(editor.zoom * 100)}%`
}

const DrawflowEditor = {
  mounted() {
    this.editor = new Drawflow(this.el)
    this.editor.reroute = true
    this.editor.curvature = 0.5
    this.editor.reroute_curvature_start_end = 0.5
    this.editor.reroute_curvature = 0.5
    this.editor.start()

    // ── Canvas toolbar ──────────────────────────────────────────────────
    // Bind to server-rendered toolbar (sibling of #drawflow-canvas)
    const toolbar = document.getElementById("df-canvas-toolbar")
    this._toolbar = toolbar
    if (toolbar) updateZoomLabel(this.editor, toolbar)

    this.editor.on("zoom", () => updateZoomLabel(this.editor, toolbar))

    toolbar.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-action]")
      if (!btn) return
      e.stopPropagation()

      switch (btn.dataset.action) {
        case "zoom-in":
          this.editor.zoom_in()
          break
        case "zoom-out":
          this.editor.zoom_out()
          break
        case "zoom-reset":
          this.editor.zoom = 1
          this.editor.canvas_x = 0
          this.editor.canvas_y = 0
          this.editor.precanvas.style.transform = "translate(0px, 0px) scale(1)"
          this.editor.dispatch("zoom", 1)
          break
        case "fit-view":
          fitView(this.editor)
          break
        case "auto-layout":
          autoLayout(this.editor)
          requestAnimationFrame(() => fitView(this.editor))
          break
        case "toggle-lock": {
          const isEdit = this.editor.editor_mode === "edit"
          this.editor.editor_mode = isEdit ? "fixed" : "edit"
          btn.classList.toggle("df-toolbar-btn-active", !isEdit)
          btn.title = isEdit ? "Unlock (view mode)" : "Toggle lock (edit/view)"
          const wrap = btn.querySelector("[data-lock-icon]")
          if (wrap) {
            const icon = wrap.querySelector("span")
            if (icon) {
              icon.className = icon.className.replace(
                /hero-lock-\w+/,
                isEdit ? "hero-lock-closed" : "hero-lock-open"
              )
            }
          }
          break
        }
      }
    })

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
      // getNodeFromId returns a deep clone (JSON.parse/stringify), so we must
      // write directly into the internal store to actually mutate Drawflow state.
      const module = this.editor.getModuleFromNodeId(id)
      const internalNode = this.editor.drawflow.drawflow[module]?.data[id]
      if (internalNode) {
        internalNode.data = { ...internalNode.data, ...data }

        // Update the node label when name changes
        const cfg = nodeConfig[internalNode.class] || {}
        const labelEl = document.querySelector(`#node-${id} .df-node-label`)
        if (labelEl) labelEl.textContent = internalNode.data.name || cfg.label || internalNode.class

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

    // ── Execution view ───────────────────────────────────────────────────────
    let execOriginalData = null
    let execCmViews = []

    const execStatusColors = {
      completed: "#10b981",
      failed:    "#ef4444",
      running:   "#3b82f6",
      pending:   "#6b7280",
      halted:    "#f59e0b",
      skipped:   "#a855f7",
    }

    const execStatusLabels = {
      completed: "completed",
      failed:    "failed",
      running:   "running",
      pending:   "pending",
      halted:    "halted",
      skipped:   "skipped",
    }

    function fmtDuration(ms) {
      if (ms == null) return ""
      return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`
    }

    // Build HTML for a data node. JSON is base64-encoded as a data attribute
    // so CodeMirror can be mounted after DOM render.
    function dataNodeHtml({ status, duration_ms, output, error }, nodeKey) {
      const color = execStatusColors[status] || execStatusColors.pending
      const dur   = fmtDuration(duration_ms)
      const json  = output != null ? JSON.stringify(output, null, 2) : null
      const b64   = json ? btoa(unescape(encodeURIComponent(json))) : null

      return `<div class="df-exec-dn">
        <div class="df-exec-dn-header">
          <span class="df-exec-dn-dot" style="background:${color}"></span>
          <span class="df-exec-dn-id" style="color:${color}">output</span>
          ${dur ? `<span class="df-exec-dn-dur">${dur}</span>` : ""}
        </div>
        ${error ? `<div class="df-exec-dn-error">${String(error).slice(0, 200)}</div>` : ""}
        ${b64 ? `<div class="df-exec-dn-cm" data-exec-key="${nodeKey}" data-b64="${b64}"></div>` : ""}
      </div>`
    }

    // Mount read-only CodeMirror JSON editors in data node placeholders.
    function mountExecCmViews() {
      document.querySelectorAll(".df-exec-dn-cm:not([data-cm-mounted])").forEach(el => {
        el.dataset.cmMounted = "1"
        let json = ""
        try { json = decodeURIComponent(escape(atob(el.dataset.b64 || ""))) } catch (_) {}
        const extensions = buildExtensions({ language: "json", readOnly: true, minimal: true, onBlur: null })
        const view = new EditorView({
          state: EditorState.create({ doc: json, extensions }),
          parent: el,
        })
        execCmViews.push(view)
      })
    }

    // Zoom + pan the canvas so all nodes fit in the viewport with padding.
    const clearExecView = () => {
      execCmViews.forEach(v => v.destroy())
      execCmViews = []
      if (execOriginalData) {
        this.editor.clear()
        this.editor.import(execOriginalData)
        execOriginalData = null
      }
    }

    this.handleEvent("load_execution_view", ({ definition, nodes }) => {
      if (!definition || !nodes || nodes.length === 0) return

      // ── Phase 1: backup original graph ────────────────────────────────────
      clearExecView()
      execOriginalData = JSON.parse(JSON.stringify(this.editor.drawflow))

      // ── Phase 2: build HTML for exec_data nodes, then convert & import ────
      const execHtmlBuilder = (type, outputs, data) => {
        if (type === "exec_data") return dataNodeHtml(data, data.source_node || "")
        return buildNodeHTML(type, outputs, data)
      }

      const drawflowData = blackboexToDrawflow(definition, execHtmlBuilder)
      this.editor.clear()
      this.editor.import(drawflowData)

      // Let Drawflow render the DOM so dagre can measure real node sizes
      requestAnimationFrame(() => {
        autoLayout(this.editor, { nodesep: 80, ranksep: 180 })

        // Recalculate SVG connection paths — Drawflow needs a frame after
        // import to measure actual port positions in the DOM (issue #914)
        const ed = this.editor
        setTimeout(() => {
          const homeData = ed.export().drawflow[ed.module].data
          Object.keys(homeData).forEach(id => ed.updateConnectionNodes(`node-${id}`))
        }, 100)

        // ── Phase 4: post-render — CodeMirror + highlights ─────────────────
        // Mount CodeMirror instances (after layout so nodes are in final position)
        mountExecCmViews()

        // Apply status highlight + pill on original executed nodes
        nodes.forEach(({ id, status, duration_ms }) => {
          const dfId = id.startsWith("n") ? id.slice(1) : id
          const el   = document.querySelector(`#node-${dfId}`)
          if (!el) return

          const color = execStatusColors[status] || execStatusColors.pending
          const label = execStatusLabels[status]  || status
          const dur   = fmtDuration(duration_ms)

          el.classList.add("df-exec-highlight")
          el.style.setProperty("--exec-color", color)

          const pill = document.createElement("div")
          pill.className = "df-exec-status-pill"
          pill.style.cssText = [
            "position:absolute", "top:-20px", "left:50%", "transform:translateX(-50%)",
            "display:inline-flex", "align-items:center", "gap:4px",
            `background:hsl(var(--card))`, `border:1.5px solid ${color}55`,
            "border-radius:999px", "padding:2px 8px",
            "font-size:9px", "font-weight:700", "font-family:ui-sans-serif,system-ui,sans-serif",
            "white-space:nowrap", "pointer-events:none", "z-index:20",
            "box-shadow:0 2px 8px rgba(0,0,0,.5)", "line-height:1.8"
          ].join(";")
          pill.innerHTML =
            `<span style="width:5px;height:5px;border-radius:50%;background:${color};display:inline-block;flex-shrink:0"></span>` +
            `<span style="color:${color}">${label}</span>` +
            (dur ? `<span style="color:#94a3b8;font-size:8px;font-family:ui-monospace,monospace">${dur}</span>` : "")
          el.appendChild(pill)
        })

      })
    })

    this.handleEvent("clear_execution_view", () => {
      clearExecView()
    })
  },

  destroyed() {
    if (this.editor) this.editor.clear()
  }
}

export default DrawflowEditor
