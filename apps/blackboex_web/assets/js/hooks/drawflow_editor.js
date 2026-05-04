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
import {
  createNodeFromDrop,
  loadDrawflowDefinition,
  setSidebarDragData,
} from "../lib/flow/drawflow_interactions";
import { wireDrawflowToolbar } from "../lib/flow/drawflow_toolbar";

const DrawflowEditor = {
  mounted() {
    this._cleanups = [];
    this._timeouts = new Set();
    this._frames = new Set();
    this._destroyed = false;

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
    this.addCleanup(
      wireDrawflowToolbar({
        editor: this.editor,
        toolbar,
        autoLayout,
        fitView,
        updateZoomLabel,
        requestFrame: (callback) => this.scheduleFrame(callback),
      }),
    );

    // Load existing definition (BlackboexFlow format from server)
    loadDrawflowDefinition(
      this.editor,
      this.el.dataset.definition,
      buildNodeHTML,
    );

    // Render output labels on condition nodes after import
    this.scheduleTimeout(() => updateAllOutputLabels(this.editor), 100);

    // ── Node selection → push to LiveView for properties drawer ──
    // Dirty flag — set by every mutation event Drawflow emits, cleared when
    // the server confirms a save or when we just imported a fresh definition
    // (e.g. on initial mount or after an AI agent run the user accepted).
    this._dataChanged = false;
    const markDirty = () => {
      this._dataChanged = true;
    };
    this.addEditorListener("nodeCreated", markDirty);
    this.addEditorListener("nodeRemoved", markDirty);
    this.addEditorListener("nodeMoved", markDirty);
    this.addEditorListener("connectionCreated", markDirty);
    this.addEditorListener("connectionRemoved", markDirty);

    this.addEditorListener("nodeSelected", (nodeId) => {
      const node = this.editor.getNodeFromId(nodeId);
      if (node) {
        this.pushEvent("node_selected", {
          id: String(nodeId),
          type: node.class,
          data: node.data || {},
        });
      }
    });

    this.addEditorListener("nodeUnselected", () => {
      this.pushEvent("node_deselected", {});
    });

    // When a node is removed, close the drawer
    this.addEditorListener("nodeRemoved", () => {
      this.pushEvent("node_deselected", {});
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
    this.addDomListener(this.el, "click", (e) => {
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
    this.addDomListener(this.el, "drop", (e) => {
      createNodeFromDrop(this.el, this.editor, e, buildNodeHTML);
    });

    this.addDomListener(this.el, "dragover", (e) => {
      e.preventDefault();
    });

    // Set up drag data on sidebar items
    document.querySelectorAll("[data-node-type]").forEach((el) => {
      this.addDomListener(el, "dragstart", (e) => {
        setSidebarDragData(el, e);
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
    this.addCleanup(() => destroyExecutionCodeMirrorViews(execCmViews));

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
      this.scheduleFrame(() => {
        if (this._destroyed) return;
        autoLayout(this.editor, { nodesep: 80, ranksep: 180 });

        // Recalculate SVG connection paths — Drawflow needs a frame after
        // import to measure actual port positions in the DOM (issue #914)
        const ed = this.editor;
        this.scheduleTimeout(() => {
          if (this._destroyed) return;
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
      this.scheduleFrame(() => {
        if (this._destroyed) return;
        const ed = this.editor;
        this.scheduleTimeout(() => {
          if (this._destroyed) return;
          const homeData = ed.export().drawflow[ed.module].data;
          Object.keys(homeData).forEach((id) =>
            ed.updateConnectionNodes(`node-${id}`),
          );
        }, 100);
      });
    });
  },

  destroyed() {
    this._destroyed = true;
    this.cleanupResources();
    if (this.editor) {
      this.editor.clear();
      this.editor = null;
    }
  },

  addCleanup(cleanup) {
    if (typeof cleanup === "function") this._cleanups.push(cleanup);
  },

  addDomListener(target, event, handler, options) {
    if (!target) return;
    target.addEventListener(event, handler, options);
    this.addCleanup(() => target.removeEventListener(event, handler, options));
  },

  addEditorListener(event, handler) {
    this.editor.on(event, handler);
    this.addCleanup(() => {
      if (this.editor?.removeListener)
        this.editor.removeListener(event, handler);
    });
  },

  scheduleTimeout(callback, delay) {
    const id = setTimeout(() => {
      this._timeouts.delete(id);
      callback();
    }, delay);
    this._timeouts.add(id);
    return id;
  },

  scheduleFrame(callback) {
    const id = requestAnimationFrame(() => {
      this._frames.delete(id);
      callback();
    });
    this._frames.add(id);
    return id;
  },

  cleanupResources() {
    this._timeouts.forEach((id) => clearTimeout(id));
    this._timeouts.clear();
    this._frames.forEach((id) => cancelAnimationFrame(id));
    this._frames.clear();
    this._cleanups
      .splice(0)
      .reverse()
      .forEach((cleanup) => cleanup());
  },
};

export default DrawflowEditor;
