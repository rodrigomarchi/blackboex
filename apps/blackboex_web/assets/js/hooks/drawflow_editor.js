import Drawflow from "../../vendor/drawflow.min.js"

// Each node type has: color accent, icon SVG, label, subtitle
const nodeConfig = {
  start: {
    color: "#10b981",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path d="M6.3 2.84A1.5 1.5 0 0 0 4 4.11v11.78a1.5 1.5 0 0 0 2.3 1.27l9.344-5.891a1.5 1.5 0 0 0 0-2.538L6.3 2.841Z" /></svg>`,
    label: "Start",
    subtitle: "Trigger"
  },
  http_request: {
    color: "#8b5cf6",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM4.332 8.027a6.012 6.012 0 0 1 1.912-2.706C6.512 5.73 6.974 6 7.5 6A1.5 1.5 0 0 1 9 7.5V8a2 2 0 0 0 4 0 2 2 0 0 1 1.523-1.943A5.977 5.977 0 0 1 16 10c0 .34-.028.675-.083 1H15a2 2 0 0 0-2 2v2.197A5.973 5.973 0 0 1 10 16v-2a2 2 0 0 0-2-2 2 2 0 0 1-2-2 2 2 0 0 0-1.668-1.973Z" clip-rule="evenodd" /></svg>`,
    label: "HTTP Request",
    subtitle: "GET / POST / PUT"
  },
  transform: {
    color: "#f59e0b",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M6.28 5.22a.75.75 0 0 1 0 1.06L2.56 10l3.72 3.72a.75.75 0 0 1-1.06 1.06L.97 10.53a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Zm7.44 0a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L17.44 10l-3.72-3.72a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" /></svg>`,
    label: "Transform",
    subtitle: "Map & filter data"
  },
  condition: {
    color: "#3b82f6",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M15.312 11.424a5.5 5.5 0 0 1-9.201 2.466l-.312-.311h2.433a.75.75 0 0 0 0-1.5H4.638a.75.75 0 0 0-.75.75v3.594a.75.75 0 0 0 1.5 0v-2.134l.429.429a7 7 0 0 0 11.712-3.138.75.75 0 0 0-1.217-.156Zm-6.624-7.74a7 7 0 0 0-11.712 3.138.75.75 0 0 0 1.217.156 5.5 5.5 0 0 1 9.201-2.466l.312.311h-2.433a.75.75 0 0 0 0 1.5h3.594a.75.75 0 0 0 .75-.75V2.003a.75.75 0 0 0-1.5 0v2.134l-.429-.429Z" clip-rule="evenodd" /></svg>`,
    label: "Condition",
    subtitle: "If / else branch"
  },
  response: {
    color: "#ef4444",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M3 4.25A2.25 2.25 0 0 1 5.25 2h5.5A2.25 2.25 0 0 1 13 4.25v2a.75.75 0 0 1-1.5 0v-2a.75.75 0 0 0-.75-.75h-5.5a.75.75 0 0 0-.75.75v11.5c0 .414.336.75.75.75h5.5a.75.75 0 0 0 .75-.75v-2a.75.75 0 0 1 1.5 0v2A2.25 2.25 0 0 1 10.75 18h-5.5A2.25 2.25 0 0 1 3 15.75V4.25Z" clip-rule="evenodd" /><path fill-rule="evenodd" d="M19 10a.75.75 0 0 0-.75-.75H8.704l1.048-.943a.75.75 0 1 0-1.004-1.114l-2.5 2.25a.75.75 0 0 0 0 1.114l2.5 2.25a.75.75 0 1 0 1.004-1.114l-1.048-.943h9.546A.75.75 0 0 0 19 10Z" clip-rule="evenodd" /></svg>`,
    label: "Response",
    subtitle: "Return result"
  },
  end: {
    color: "#6b7280",
    icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="df-node-icon"><path fill-rule="evenodd" d="M2 10a8 8 0 1 1 16 0 8 8 0 0 1-16 0Zm5-2.25A.75.75 0 0 1 7.75 7h.5a.75.75 0 0 1 .75.75v4.5a.75.75 0 0 1-.75.75h-.5a.75.75 0 0 1-.75-.75v-4.5Zm4 0a.75.75 0 0 1 .75-.75h.5a.75.75 0 0 1 .75.75v4.5a.75.75 0 0 1-.75.75h-.5a.75.75 0 0 1-.75-.75v-4.5Z" clip-rule="evenodd" /></svg>`,
    label: "End",
    subtitle: "Stop flow"
  }
}

function buildNodeHTML(type) {
  const cfg = nodeConfig[type]
  if (!cfg) return `<div class="df-node"><strong>${type}</strong></div>`

  return `<div class="df-node" style="--node-color: ${cfg.color}">
    <div class="df-node-header">
      <div class="df-node-icon-wrap" style="background: ${cfg.color}15; color: ${cfg.color}">
        ${cfg.icon}
      </div>
      <div class="df-node-text">
        <div class="df-node-label">${cfg.label}</div>
        <div class="df-node-subtitle">${cfg.subtitle}</div>
      </div>
    </div>
  </div>`
}

const DrawflowEditor = {
  mounted() {
    this.editor = new Drawflow(this.el)
    this.editor.reroute = true
    this.editor.curvature = 0.5
    this.editor.reroute_curvature_start_end = 0.5
    this.editor.reroute_curvature = 0.5
    this.editor.start()

    // Load existing definition
    const definition = this.el.dataset.definition
    if (definition) {
      try {
        const parsed = JSON.parse(definition)
        if (parsed && parsed.drawflow) {
          this.editor.import(parsed)
        }
      } catch (_e) {
        // Empty or invalid definition — start fresh
      }
    }

    // Handle drag-drop from sidebar
    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      const type = e.dataTransfer.getData("node-type")
      const inputs = parseInt(e.dataTransfer.getData("node-inputs") || "1")
      const outputs = parseInt(e.dataTransfer.getData("node-outputs") || "1")

      if (type) {
        const html = buildNodeHTML(type)
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

    // Server asks us to export the definition for saving
    this.handleEvent("export_definition", () => {
      const data = this.editor.export()
      this.pushEvent("save_definition", { definition: data })
    })

    // Server confirms save
    this.handleEvent("definition_saved", () => {
      // LiveView handles the "Saved" indicator
    })
  },

  destroyed() {
    if (this.editor) {
      this.editor.clear()
    }
  }
}

export default DrawflowEditor
