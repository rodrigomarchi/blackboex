/**
 * @file Tiptap code block node view with language selection and Mermaid preview support.
 *
 * Extends CodeBlockLowlight with a per-block language selector. Mermaid blocks render
 * as SVG previews when the selection leaves the block, but switch back to editable code
 * when focused so the ProseMirror document remains the source of truth.
 */
import CodeBlockLowlight from "@tiptap/extension-code-block-lowlight";

// Lazy-load bundled mermaid only when the user creates a mermaid block.
let mermaidModule = null;
let mermaidLoadPromise = null;
let mermaidLoader = async () => {
  const { default: mermaid } = await import("mermaid");
  return mermaid;
};

/**
 * Overrides the lazy Mermaid importer and clears cached state for deterministic tests.
 * @param {Function} loader - Async function that resolves to the Mermaid module.
 * @returns {void}
 */
export function setMermaidLoader(loader) {
  mermaidModule = null;
  mermaidLoadPromise = null;
  mermaidLoader = loader;
}

/**
 * Loads Mermaid once, initializes it with editor-safe rendering options, and caches it.
 * @returns {Promise<object>} Initialized Mermaid module.
 */
export async function getMermaid() {
  if (mermaidModule) return mermaidModule;
  if (mermaidLoadPromise) return mermaidLoadPromise;

  mermaidLoadPromise = (async () => {
    const mermaid = await mermaidLoader();
    mermaid.initialize({
      startOnLoad: false,
      theme: "dark",
      securityLevel: "loose",
      fontFamily: "ui-sans-serif, system-ui, sans-serif",
    });
    mermaidModule = mermaid;
    return mermaid;
  })();

  try {
    return await mermaidLoadPromise;
  } catch (err) {
    mermaidLoadPromise = null;
    throw err;
  }
}

// Serialize mermaid.render() calls — concurrent renders cause silent failures
let renderQueue = Promise.resolve();

/**
 * Serializes Mermaid renders so concurrent node views do not race inside Mermaid.
 * @param {string} id - Unique render id for Mermaid's generated SVG.
 * @param {string} text - Mermaid diagram source.
 * @returns {Promise<{svg: string}>} Mermaid render result.
 */
export function enqueueRender(id, text) {
  const task = renderQueue.then(async () => {
    const mermaid = await getMermaid();
    return await mermaid.render(id, text);
  });
  renderQueue = task.catch(() => {});
  return task;
}

/**
 * Makes Mermaid SVG output responsive inside the editor preview container.
 * @param {SVGElement | null} svgEl - Rendered Mermaid SVG element.
 * @returns {void}
 */
export function fitSvg(svgEl) {
  if (!svgEl) return;
  const w = svgEl.getAttribute("width");
  const h = svgEl.getAttribute("height");
  if (w && h && !svgEl.getAttribute("viewBox")) {
    svgEl.setAttribute("viewBox", `0 0 ${parseFloat(w)} ${parseFloat(h)}`);
  }
  svgEl.removeAttribute("width");
  svgEl.removeAttribute("height");
  svgEl.style.width = "100%";
  svgEl.style.height = "auto";
  svgEl.style.maxHeight = "600px";
}

/**
 * Human-readable labels for the language selector, including virtual Mermaid mode.
 */
export const LANG_LABELS = {
  plaintext: "Plain Text",
  javascript: "JavaScript",
  typescript: "TypeScript",
  python: "Python",
  elixir: "Elixir",
  ruby: "Ruby",
  go: "Go",
  rust: "Rust",
  java: "Java",
  c: "C",
  cpp: "C++",
  csharp: "C#",
  php: "PHP",
  swift: "Swift",
  kotlin: "Kotlin",
  html: "HTML",
  xml: "XML",
  css: "CSS",
  scss: "SCSS",
  json: "JSON",
  yaml: "YAML",
  sql: "SQL",
  graphql: "GraphQL",
  bash: "Bash",
  shell: "Shell",
  dockerfile: "Dockerfile",
  diff: "Diff",
  markdown: "Markdown",
  mermaid: "Mermaid",
};

let mermaidIdCounter = 0;

/**
 * CodeBlockLowlight extension used by the rich editor.
 *
 * The node view owns toolbar DOM, preview DOM, selection tracking, delayed Mermaid
 * renders, responsive SVG fitting, and cleanup of editor event subscriptions.
 */
export const CodeBlockWithLang = CodeBlockLowlight.extend({
  addNodeView() {
    return ({ node, editor, getPos }) => {
      let currentNode = node;
      let isFocused = false;
      let renderTimer = null;
      let zoomLevel = 1;
      const mermaidId = `mermaid-${++mermaidIdCounter}`;

      const isMermaid = () => (currentNode.attrs.language || "") === "mermaid";

      // ── DOM structure ─────────────────────────────────────
      const dom = document.createElement("div");
      dom.className = "tiptap-code-block-wrapper";

      // Toolbar with language selector
      const toolbar = document.createElement("div");
      toolbar.className = "tiptap-cb-toolbar";
      toolbar.contentEditable = "false";

      const select = document.createElement("select");
      select.className = "tiptap-cb-lang-select";

      const langs = [
        ...this.options.lowlight.listLanguages(),
        "mermaid",
      ].sort();
      const seen = new Set();
      langs.forEach((lang) => {
        if (seen.has(lang)) return;
        seen.add(lang);
        const opt = document.createElement("option");
        opt.value = lang;
        opt.textContent = LANG_LABELS[lang] || lang;
        select.appendChild(opt);
      });

      select.value = node.attrs.language || "plaintext";

      select.addEventListener("change", (e) => {
        if (typeof getPos === "function") {
          const tr = editor.view.state.tr.setNodeMarkup(getPos(), undefined, {
            ...currentNode.attrs,
            language: e.target.value,
          });
          editor.view.dispatch(tr);
        }
      });

      select.addEventListener("mousedown", (e) => e.stopPropagation());
      select.addEventListener("keydown", (e) => e.stopPropagation());

      toolbar.appendChild(select);
      dom.appendChild(toolbar);

      // Code area (pre > code)
      const pre = document.createElement("pre");
      pre.setAttribute("spellcheck", "false");
      const code = document.createElement("code");
      code.className = `language-${node.attrs.language || "plaintext"}`;
      pre.appendChild(code);
      dom.appendChild(pre);

      // Mermaid preview overlay (visibility controlled by CSS class on dom)
      const preview = document.createElement("div");
      preview.className = "tiptap-mermaid-preview";
      preview.contentEditable = "false";
      dom.appendChild(preview);

      // SVG container inside preview (for zoom transforms)
      const svgContainer = document.createElement("div");
      svgContainer.className = "tiptap-mermaid-svg-container";
      preview.appendChild(svgContainer);

      // ── Zoom controls ─────────────────────────────────────
      const zoomBar = document.createElement("div");
      zoomBar.className = "tiptap-mermaid-zoom-bar";
      zoomBar.contentEditable = "false";

      const zoomLabel = document.createElement("span");
      zoomLabel.className = "tiptap-mermaid-zoom-label";
      zoomLabel.textContent = "100%";

      const btnZoomOut = document.createElement("button");
      btnZoomOut.type = "button";
      btnZoomOut.textContent = "−";
      btnZoomOut.title = "Zoom out";
      btnZoomOut.className = "tiptap-mermaid-zoom-btn";

      const btnZoomIn = document.createElement("button");
      btnZoomIn.type = "button";
      btnZoomIn.textContent = "+";
      btnZoomIn.title = "Zoom in";
      btnZoomIn.className = "tiptap-mermaid-zoom-btn";

      const btnFit = document.createElement("button");
      btnFit.type = "button";
      btnFit.textContent = "⤢";
      btnFit.title = "Fit to width";
      btnFit.className = "tiptap-mermaid-zoom-btn";

      function applyZoom(newZoom) {
        zoomLevel = Math.max(0.25, Math.min(3, newZoom));
        svgContainer.style.transform = `scale(${zoomLevel})`;
        svgContainer.style.transformOrigin = "top center";
        zoomLabel.textContent = `${Math.round(zoomLevel * 100)}%`;
      }

      btnZoomIn.addEventListener("click", (e) => {
        e.stopPropagation();
        applyZoom(zoomLevel + 0.25);
      });
      btnZoomOut.addEventListener("click", (e) => {
        e.stopPropagation();
        applyZoom(zoomLevel - 0.25);
      });
      btnFit.addEventListener("click", (e) => {
        e.stopPropagation();
        applyZoom(1);
      });

      // Prevent clicks on zoom bar from focusing the code editor
      zoomBar.addEventListener("mousedown", (e) => e.stopPropagation());
      zoomBar.addEventListener("click", (e) => e.stopPropagation());

      zoomBar.append(btnZoomOut, zoomLabel, btnZoomIn, btnFit);
      preview.appendChild(zoomBar);

      // Click on SVG area → focus the code editor
      svgContainer.addEventListener("click", () => {
        if (typeof getPos === "function") {
          editor.commands.setTextSelection(getPos() + 1);
          editor.commands.focus();
        }
      });

      // ── Mermaid rendering ─────────────────────────────────

      async function renderMermaid() {
        if (!isMermaid()) return;

        const text = currentNode.textContent.trim();
        if (!text) {
          svgContainer.innerHTML =
            '<span class="tiptap-mermaid-empty">Empty diagram — type Mermaid syntax</span>';
          zoomBar.style.display = "none";
          return;
        }

        svgContainer.innerHTML =
          '<span class="tiptap-mermaid-loading">Loading diagram…</span>';
        zoomBar.style.display = "none";

        try {
          const { svg } = await enqueueRender(mermaidId, text);
          svgContainer.innerHTML = svg;

          // Auto-fit: make SVG responsive within container
          const svgEl = svgContainer.querySelector("svg");
          fitSvg(svgEl);

          preview.classList.remove("tiptap-mermaid-error");
          zoomBar.style.display = "";
          applyZoom(1);
        } catch (err) {
          svgContainer.innerHTML = `<span class="tiptap-mermaid-error-msg">${err.message || "Invalid diagram"}</span>`;
          preview.classList.add("tiptap-mermaid-error");
          zoomBar.style.display = "none";
          const broken = document.getElementById("d" + mermaidId);
          if (broken) broken.remove();
        }
      }

      function scheduleRender() {
        clearTimeout(renderTimer);
        renderTimer = setTimeout(renderMermaid, 400);
      }

      function syncVisibility() {
        if (isMermaid()) {
          dom.classList.add("is-mermaid");
          if (isFocused) {
            // Editing: show code, hide preview
            pre.style.display = "";
            preview.style.display = "none";
          } else {
            // Blurred: hide code, show preview (natural height, no overlay)
            pre.style.display = "none";
            preview.style.display = "flex";
            scheduleRender();
          }
        } else {
          pre.style.display = "";
          preview.style.display = "none";
          dom.classList.remove("is-mermaid");
        }
      }

      syncVisibility();

      // ── Focus tracking ────────────────────────────────────

      function onFocus() {
        isFocused = true;
        syncVisibility();
      }

      function onBlur() {
        isFocused = false;
        syncVisibility();
      }

      const onSelectionUpdate = () => {
        if (typeof getPos !== "function") return;
        const pos = getPos();
        const { from, to } = editor.state.selection;
        const nodeSize = currentNode.nodeSize;
        const inside = from >= pos && to <= pos + nodeSize;
        if (inside && !isFocused) onFocus();
        else if (!inside && isFocused) onBlur();
      };

      editor.on("selectionUpdate", onSelectionUpdate);

      // ── NodeView interface ────────────────────────────────

      return {
        dom,
        contentDOM: code,

        update(updatedNode) {
          if (updatedNode.type.name !== "codeBlock") return false;
          const langChanged =
            currentNode.attrs.language !== updatedNode.attrs.language;
          currentNode = updatedNode;
          const lang = updatedNode.attrs.language || "plaintext";
          select.value = lang;
          code.className = `language-${lang}`;

          if (langChanged) syncVisibility();
          if (isMermaid() && !isFocused) scheduleRender();

          return true;
        },

        // Tell ProseMirror to ignore DOM mutations in toolbar and preview —
        // without this, mermaid SVG insertion triggers MutationObserver →
        // transaction → onUpdate → infinite NodeView recreation.
        ignoreMutation(mutation) {
          if (
            preview.contains(mutation.target) ||
            mutation.target === preview
          ) {
            return true;
          }
          if (
            toolbar.contains(mutation.target) ||
            mutation.target === toolbar
          ) {
            return true;
          }
          return false;
        },

        selectNode() {
          onFocus();
        },
        deselectNode() {
          onBlur();
        },

        destroy() {
          clearTimeout(renderTimer);
          editor.off("selectionUpdate", onSelectionUpdate);
        },
      };
    };
  },
});
