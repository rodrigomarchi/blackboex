import Drawflow from "../../vendor/drawflow.min.js";
import {
  drawflowToBlackboex,
  blackboexToDrawflow,
} from "../lib/flow/drawflow_converter";
import {
  applyExecutionHighlights,
  buildExecutionDataNodeHtml,
  destroyExecutionCodeMirrorViews,
  mountExecutionCodeMirrorViews,
} from "../lib/flow/execution_view";
import {
  buildNodeHTML,
  countOutputs,
  nodeConfig,
  updateAllOutputLabels,
  updateConditionLabel,
  updateOutputLabels,
} from "../lib/flow/node_catalog";
import {
  autoLayout,
  fitView,
  updateZoomLabel,
} from "../lib/flow/drawflow_layout";

const DrawflowEditor = {
  mounted() {
    this.editor = new Drawflow(this.el);
    this.editor.reroute = true;
    this.editor.curvature = 0.5;
    this.editor.reroute_curvature_start_end = 0.5;
    this.editor.reroute_curvature = 0.5;
    this.editor.start();

    // ── Canvas toolbar ──────────────────────────────────────────────────
    // Bind to server-rendered toolbar (sibling of #drawflow-canvas)
    const toolbar = document.getElementById("df-canvas-toolbar");
    this._toolbar = toolbar;
    if (toolbar) updateZoomLabel(this.editor, toolbar);

    this.editor.on("zoom", () => updateZoomLabel(this.editor, toolbar));

    toolbar.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-action]");
      if (!btn) return;
      e.stopPropagation();

      switch (btn.dataset.action) {
        case "zoom-in":
          this.editor.zoom_in();
          break;
        case "zoom-out":
          this.editor.zoom_out();
          break;
        case "zoom-reset":
          this.editor.zoom = 1;
          this.editor.canvas_x = 0;
          this.editor.canvas_y = 0;
          this.editor.precanvas.style.transform =
            "translate(0px, 0px) scale(1)";
          this.editor.dispatch("zoom", 1);
          break;
        case "fit-view":
          fitView(this.editor);
          break;
        case "auto-layout":
          autoLayout(this.editor);
          requestAnimationFrame(() => fitView(this.editor));
          break;
        case "toggle-lock": {
          const isEdit = this.editor.editor_mode === "edit";
          this.editor.editor_mode = isEdit ? "fixed" : "edit";
          btn.classList.toggle("df-toolbar-btn-active", !isEdit);
          btn.title = isEdit ? "Unlock (view mode)" : "Toggle lock (edit/view)";
          const wrap = btn.querySelector("[data-lock-icon]");
          if (wrap) {
            const icon = wrap.querySelector("span");
            if (icon) {
              icon.className = icon.className.replace(
                /hero-lock-\w+/,
                isEdit ? "hero-lock-closed" : "hero-lock-open",
              );
            }
          }
          break;
        }
      }
    });

    // Load existing definition (BlackboexFlow format from server)
    const definition = this.el.dataset.definition;
    if (definition) {
      try {
        const parsed = JSON.parse(definition);
        if (parsed && parsed.version && parsed.nodes) {
          // Convert BlackboexFlow → Drawflow for the editor
          const drawflowData = blackboexToDrawflow(parsed, buildNodeHTML);
          this.editor.import(drawflowData);
        } else if (parsed && parsed.drawflow) {
          // Legacy: raw Drawflow JSON (backwards compat during migration)
          this.editor.import(parsed);
        }
      } catch {
        // Empty or invalid definition — start fresh
      }
    }

    // Render output labels on condition nodes after import
    setTimeout(() => updateAllOutputLabels(this.editor), 100);

    // ── Node selection → push to LiveView for properties drawer ──
    // Dirty flag — set by every mutation event Drawflow emits, cleared when
    // the server confirms a save or when we just imported a fresh definition
    // (e.g. on initial mount or after an AI agent run the user accepted).
    this._dataChanged = false;
    const markDirty = () => {
      this._dataChanged = true;
    };
    this.editor.on("nodeCreated", markDirty);
    this.editor.on("nodeRemoved", markDirty);
    this.editor.on("nodeMoved", markDirty);
    this.editor.on("connectionCreated", markDirty);
    this.editor.on("connectionRemoved", markDirty);

    this.editor.on("nodeSelected", (nodeId) => {
      const node = this.editor.getNodeFromId(nodeId);
      if (node) {
        this.pushEvent("node_selected", {
          id: String(nodeId),
          type: node.class,
          data: node.data || {},
        });
      }
    });

    this.editor.on("nodeUnselected", () => {
      this.pushEvent("node_deselected", {});
    });

    // When a node is removed, close the drawer
    this.editor.on("nodeRemoved", () => {
      this.pushEvent("node_deselected", {});
    });

    // Also close drawer when clicking empty canvas
    this.editor.on("click", () => {
      // Drawflow fires nodeUnselected separately, but this catches edge cases
    });

    // ── Server pushes updated data back to a node ──
    this.handleEvent("set_node_data", ({ id, data }) => {
      // getNodeFromId returns a deep clone (JSON.parse/stringify), so we must
      // write directly into the internal store to actually mutate Drawflow state.
      const module = this.editor.getModuleFromNodeId(id);
      const internalNode = this.editor.drawflow.drawflow[module]?.data[id];
      if (internalNode) {
        internalNode.data = { ...internalNode.data, ...data };

        // Update the node label when name changes
        const cfg = nodeConfig[internalNode.class] || {};
        const labelEl = document.querySelector(`#node-${id} .df-node-label`);
        if (labelEl) {
          labelEl.textContent =
            internalNode.data.name || cfg.label || internalNode.class;
        }

        // Update output labels if branch_labels changed
        if (data.branch_labels) {
          updateOutputLabels(this.editor, id);
        }
      }
    });

    // ── Condition node +/- buttons ──
    this.el.addEventListener("click", (e) => {
      const addBtn = e.target.closest(".df-btn-add-output");
      const removeBtn = e.target.closest(".df-btn-remove-output");

      if (addBtn || removeBtn) {
        e.stopPropagation();
        const nodeEl = e.target.closest(".drawflow-node");
        if (!nodeEl) return;
        const nodeId = nodeEl.id.replace("node-", "");

        if (addBtn) {
          this.editor.addNodeOutput(nodeId);
          updateConditionLabel(this.editor, nodeId);
          updateOutputLabels(this.editor, nodeId);
        }

        if (removeBtn) {
          const outputs = countOutputs(this.editor, nodeId);
          if (outputs > 1) {
            this.editor.removeNodeOutput(nodeId, `output_${outputs}`);
            updateConditionLabel(this.editor, nodeId);
            updateOutputLabels(this.editor, nodeId);
          }
        }
      }
    });

    // ── Drag-drop from sidebar ──
    this.el.addEventListener("drop", (e) => {
      e.preventDefault();
      const type = e.dataTransfer.getData("node-type");
      const inputs = parseInt(e.dataTransfer.getData("node-inputs") || "1");
      const outputs = parseInt(e.dataTransfer.getData("node-outputs") || "1");

      if (type) {
        const html = buildNodeHTML(type, outputs, {});
        const rect = this.el.getBoundingClientRect();
        const x =
          (e.clientX -
            rect.left -
            this.editor.precanvas.getBoundingClientRect().left +
            this.editor.canvas_x) /
          this.editor.zoom;
        const y =
          (e.clientY -
            rect.top -
            this.editor.precanvas.getBoundingClientRect().top +
            this.editor.canvas_y) /
          this.editor.zoom;

        this.editor.addNode(type, inputs, outputs, x, y, type, {}, html);
      }
    });

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault();
    });

    // Set up drag data on sidebar items
    document.querySelectorAll("[data-node-type]").forEach((el) => {
      el.addEventListener("dragstart", (e) => {
        e.dataTransfer.setData("node-type", el.dataset.nodeType);
        e.dataTransfer.setData("node-label", el.dataset.nodeLabel);
        e.dataTransfer.setData("node-inputs", el.dataset.nodeInputs);
        e.dataTransfer.setData("node-outputs", el.dataset.nodeOutputs);
      });
    });

    // ── Save/load events ──
    this.handleEvent("export_definition", () => {
      const drawflowData = this.editor.export();
      const blackboexData = drawflowToBlackboex(drawflowData);
      this.pushEvent("save_definition", { definition: blackboexData });
    });

    this.handleEvent("definition_saved", () => {
      this._dataChanged = false;
    });

    // JSON preview modal — show BlackboexFlow format
    this.handleEvent("export_json_preview", () => {
      const drawflowData = this.editor.export();
      const blackboexData = drawflowToBlackboex(drawflowData);
      this.pushEvent("show_json_preview", { definition: blackboexData });
    });

    // ── Execution view ───────────────────────────────────────────────────────
    let execOriginalData = null;
    let execCmViews = [];

    // Zoom + pan the canvas so all nodes fit in the viewport with padding.
    const clearExecView = () => {
      destroyExecutionCodeMirrorViews(execCmViews);
      execCmViews = [];
      if (execOriginalData) {
        this.editor.clear();
        this.editor.import(execOriginalData);
        execOriginalData = null;
      }
    };

    this.handleEvent("load_execution_view", ({ definition, nodes }) => {
      if (!definition || !nodes || nodes.length === 0) return;

      // ── Phase 1: backup original graph ────────────────────────────────────
      clearExecView();
      execOriginalData = JSON.parse(JSON.stringify(this.editor.drawflow));

      // ── Phase 2: build HTML for exec_data nodes, then convert & import ────
      const execHtmlBuilder = (type, outputs, data) => {
        if (type === "exec_data") {
          return buildExecutionDataNodeHtml(data, data.source_node || "");
        }
        return buildNodeHTML(type, outputs, data);
      };

      const drawflowData = blackboexToDrawflow(definition, execHtmlBuilder);
      this.editor.clear();
      this.editor.import(drawflowData);

      // Let Drawflow render the DOM so dagre can measure real node sizes
      requestAnimationFrame(() => {
        autoLayout(this.editor, { nodesep: 80, ranksep: 180 });

        // Recalculate SVG connection paths — Drawflow needs a frame after
        // import to measure actual port positions in the DOM (issue #914)
        const ed = this.editor;
        setTimeout(() => {
          const homeData = ed.export().drawflow[ed.module].data;
          Object.keys(homeData).forEach((id) =>
            ed.updateConnectionNodes(`node-${id}`),
          );
        }, 100);

        // ── Phase 4: post-render — CodeMirror + highlights ─────────────────
        // Mount CodeMirror instances (after layout so nodes are in final position)
        execCmViews = mountExecutionCodeMirrorViews();

        // Apply status highlight + pill on original executed nodes
        applyExecutionHighlights(nodes);
      });
    });

    this.handleEvent("clear_execution_view", () => {
      clearExecView();
    });

    // ── Flow AI Agent: replace canvas with LLM-generated definition ──────────
    this.handleEvent("flow_chat:reload_definition", ({ definition }) => {
      if (!definition || !Array.isArray(definition.nodes)) return;

      // Guard against silently wiping out in-flight user edits. `dataChanged`
      // is toggled on by the change handlers (node moves, edge creates,
      // property updates) and cleared on explicit save. If the user has
      // pending changes, ask before replacing. They can still cancel.
      if (this._dataChanged) {
        const proceed = window.confirm(
          "Você tem alterações não salvas no canvas. " +
            "Aplicar a resposta do agente vai sobrescrevê-las. Continuar?",
        );
        if (!proceed) return;
      }

      const drawflowData = blackboexToDrawflow(definition, buildNodeHTML);
      this.editor.clear();
      this.editor.import(drawflowData);
      this._dataChanged = false;

      // Drawflow needs a frame after import to measure actual port positions in
      // the DOM before connection SVG paths render correctly (issue #914).
      requestAnimationFrame(() => {
        const ed = this.editor;
        setTimeout(() => {
          const homeData = ed.export().drawflow[ed.module].data;
          Object.keys(homeData).forEach((id) =>
            ed.updateConnectionNodes(`node-${id}`),
          );
        }, 100);
      });
    });
  },

  destroyed() {
    if (this.editor) this.editor.clear();
  },
};

export default DrawflowEditor;
