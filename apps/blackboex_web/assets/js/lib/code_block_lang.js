/**
 * Extends CodeBlockLowlight with a language selector dropdown.
 *
 * Uses Tiptap's addNodeView to render a <select> inside each code block,
 * so it's part of the ProseMirror node lifecycle (not a DOM observer hack).
 */
import CodeBlockLowlight from "@tiptap/extension-code-block-lowlight"

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
}

export const CodeBlockWithLang = CodeBlockLowlight.extend({
  addNodeView() {
    return ({ node, editor, getPos }) => {
      // Track current attrs for the change handler
      let currentNode = node

      // Outer wrapper
      const dom = document.createElement("div")
      dom.className = "tiptap-code-block-wrapper"

      // Language selector bar
      const toolbar = document.createElement("div")
      toolbar.className = "tiptap-cb-toolbar"
      toolbar.contentEditable = "false"

      const select = document.createElement("select")
      select.className = "tiptap-cb-lang-select"

      // Build options from registered lowlight languages
      const langs = this.options.lowlight.listLanguages().sort()
      langs.forEach((lang) => {
        const opt = document.createElement("option")
        opt.value = lang
        opt.textContent = LANG_LABELS[lang] || lang
        select.appendChild(opt)
      })

      select.value = node.attrs.language || "plaintext"

      select.addEventListener("change", (e) => {
        if (typeof getPos === "function") {
          const pos = getPos()
          const tr = editor.view.state.tr.setNodeMarkup(pos, undefined, {
            ...currentNode.attrs,
            language: e.target.value,
          })
          editor.view.dispatch(tr)
        }
      })

      // Prevent ProseMirror from stealing events
      select.addEventListener("mousedown", (e) => e.stopPropagation())
      select.addEventListener("keydown", (e) => e.stopPropagation())

      toolbar.appendChild(select)
      dom.appendChild(toolbar)

      // The actual <pre><code> content area
      const pre = document.createElement("pre")
      pre.setAttribute("spellcheck", "false")
      const code = document.createElement("code")
      code.className = `language-${node.attrs.language || "plaintext"}`
      pre.appendChild(code)
      dom.appendChild(pre)

      return {
        dom,
        contentDOM: code,
        update(updatedNode) {
          if (updatedNode.type.name !== "codeBlock") return false
          currentNode = updatedNode
          const lang = updatedNode.attrs.language || "plaintext"
          select.value = lang
          code.className = `language-${lang}`
          return true
        },
      }
    }
  },
})
