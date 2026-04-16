/**
 * Extends CodeBlockLowlight with:
 * 1. Language selector dropdown on every code block
 * 2. Mermaid diagram rendering (dual-mode: code when focused, SVG when blurred)
 */
import CodeBlockLowlight from "@tiptap/extension-code-block-lowlight"

// Lazy-load mermaid from CDN — only downloaded when user creates a mermaid block.
// Marked as --external:mermaid in esbuild so it's not bundled (~7MB savings).
let mermaidModule = null
async function getMermaid() {
  if (mermaidModule) return mermaidModule

  // Dynamic import from ESM CDN
  const { default: mermaid } = await import(
    /* webpackIgnore: true */
    "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs"
  )
  mermaid.initialize({
    startOnLoad: false,
    theme: "dark",
    securityLevel: "loose",
    fontFamily: "ui-sans-serif, system-ui, sans-serif",
  })
  mermaidModule = mermaid
  return mermaid
}

const LANG_LABELS = {
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
}

let mermaidIdCounter = 0

export const CodeBlockWithLang = CodeBlockLowlight.extend({
  addNodeView() {
    return ({ node, editor, getPos }) => {
      let currentNode = node
      let isFocused = false
      let renderTimer = null
      const mermaidId = `mermaid-${++mermaidIdCounter}`

      const isMermaid = () => (currentNode.attrs.language || "") === "mermaid"

      // ── DOM structure ─────────────────────────────────────
      const dom = document.createElement("div")
      dom.className = "tiptap-code-block-wrapper"

      // Toolbar with language selector
      const toolbar = document.createElement("div")
      toolbar.className = "tiptap-cb-toolbar"
      toolbar.contentEditable = "false"

      const select = document.createElement("select")
      select.className = "tiptap-cb-lang-select"

      // Add "mermaid" to the language list alongside lowlight languages
      const langs = [...this.options.lowlight.listLanguages(), "mermaid"].sort()
      const seen = new Set()
      langs.forEach((lang) => {
        if (seen.has(lang)) return
        seen.add(lang)
        const opt = document.createElement("option")
        opt.value = lang
        opt.textContent = LANG_LABELS[lang] || lang
        select.appendChild(opt)
      })

      select.value = node.attrs.language || "plaintext"

      select.addEventListener("change", (e) => {
        if (typeof getPos === "function") {
          const tr = editor.view.state.tr.setNodeMarkup(getPos(), undefined, {
            ...currentNode.attrs,
            language: e.target.value,
          })
          editor.view.dispatch(tr)
        }
      })

      select.addEventListener("mousedown", (e) => e.stopPropagation())
      select.addEventListener("keydown", (e) => e.stopPropagation())

      toolbar.appendChild(select)
      dom.appendChild(toolbar)

      // Code area (pre > code)
      const pre = document.createElement("pre")
      pre.setAttribute("spellcheck", "false")
      const code = document.createElement("code")
      code.className = `language-${node.attrs.language || "plaintext"}`
      pre.appendChild(code)
      dom.appendChild(pre)

      // Mermaid preview overlay (hidden by default)
      const preview = document.createElement("div")
      preview.className = "tiptap-mermaid-preview"
      preview.contentEditable = "false"
      preview.style.display = "none"
      dom.appendChild(preview)

      // Click on preview → focus the code
      preview.addEventListener("click", () => {
        if (typeof getPos === "function") {
          editor.commands.setTextSelection(getPos() + 1)
          editor.commands.focus()
        }
      })

      // ── Mermaid rendering ─────────────────────────────────

      async function renderMermaid() {
        if (!isMermaid()) return

        const text = currentNode.textContent.trim()
        if (!text) {
          preview.innerHTML = '<span class="tiptap-mermaid-empty">Empty diagram — type Mermaid syntax</span>'
          return
        }

        const mermaid = await getMermaid()

        try {
          const { svg } = await mermaid.render(mermaidId, text)
          preview.innerHTML = svg
          preview.classList.remove("tiptap-mermaid-error")
        } catch (err) {
          preview.innerHTML = `<span class="tiptap-mermaid-error-msg">${err.message || "Invalid diagram"}</span>`
          preview.classList.add("tiptap-mermaid-error")
          // mermaid leaves a broken element in the DOM — clean it up
          const broken = document.getElementById("d" + mermaidId)
          if (broken) broken.remove()
        }
      }

      function scheduleRender() {
        clearTimeout(renderTimer)
        renderTimer = setTimeout(renderMermaid, 400)
      }

      function syncVisibility() {
        if (isMermaid()) {
          if (isFocused) {
            // Editing: show code, hide preview
            pre.style.display = ""
            preview.style.display = "none"
          } else {
            // Blurred: show preview, hide code
            pre.style.display = "none"
            preview.style.display = ""
            scheduleRender()
          }
          dom.classList.add("is-mermaid")
        } else {
          // Normal code block: always show code, hide preview
          pre.style.display = ""
          preview.style.display = "none"
          dom.classList.remove("is-mermaid")
        }
      }

      // Initial render
      syncVisibility()

      // ── Focus tracking ────────────────────────────────────

      function onFocus() {
        isFocused = true
        syncVisibility()
      }

      function onBlur() {
        isFocused = false
        syncVisibility()
      }

      // Listen for selection changes to detect focus in/out of this node
      const onSelectionUpdate = () => {
        if (typeof getPos !== "function") return
        const pos = getPos()
        const { from, to } = editor.state.selection
        const nodeSize = currentNode.nodeSize
        const inside = from >= pos && to <= pos + nodeSize
        if (inside && !isFocused) onFocus()
        else if (!inside && isFocused) onBlur()
      }

      editor.on("selectionUpdate", onSelectionUpdate)

      // ── NodeView interface ────────────────────────────────

      return {
        dom,
        contentDOM: code,

        update(updatedNode) {
          if (updatedNode.type.name !== "codeBlock") return false
          const langChanged = currentNode.attrs.language !== updatedNode.attrs.language
          currentNode = updatedNode
          const lang = updatedNode.attrs.language || "plaintext"
          select.value = lang
          code.className = `language-${lang}`

          if (langChanged) syncVisibility()
          if (isMermaid() && !isFocused) scheduleRender()

          return true
        },

        selectNode() { onFocus() },
        deselectNode() { onBlur() },

        destroy() {
          clearTimeout(renderTimer)
          editor.off("selectionUpdate", onSelectionUpdate)
        },
      }
    }
  },
})
