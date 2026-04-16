import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import { Markdown } from "tiptap-markdown"
import Placeholder from "@tiptap/extension-placeholder"
import Typography from "@tiptap/extension-typography"
import TaskList from "@tiptap/extension-task-list"
import TaskItem from "@tiptap/extension-task-item"
// CodeBlockLowlight imported via code_block_lang.js extension
import BubbleMenu from "@tiptap/extension-bubble-menu"
import Link from "@tiptap/extension-link"
import Image from "@tiptap/extension-image"
import Highlight from "@tiptap/extension-highlight"
import Underline from "@tiptap/extension-underline"
import Subscript from "@tiptap/extension-subscript"
import Superscript from "@tiptap/extension-superscript"
import Table from "@tiptap/extension-table"
import TableRow from "@tiptap/extension-table-row"
import TableCell from "@tiptap/extension-table-cell"
import TableHeader from "@tiptap/extension-table-header"
import TextAlign from "@tiptap/extension-text-align"
import TextStyle from "@tiptap/extension-text-style"
import Color from "@tiptap/extension-color"
import CharacterCount from "@tiptap/extension-character-count"
import { createLowlight } from "lowlight"
import { SlashCommands, createSlashSuggestion } from "../lib/slash_commands"
import { CodeBlockWithLang } from "../lib/code_block_lang"

// Load popular languages individually for smaller bundle (vs `all` which adds ~1.5MB)
import javascript from "highlight.js/lib/languages/javascript"
import typescript from "highlight.js/lib/languages/typescript"
import python from "highlight.js/lib/languages/python"
import elixir from "highlight.js/lib/languages/elixir"
import ruby from "highlight.js/lib/languages/ruby"
import go from "highlight.js/lib/languages/go"
import rust from "highlight.js/lib/languages/rust"
import java from "highlight.js/lib/languages/java"
import c from "highlight.js/lib/languages/c"
import cpp from "highlight.js/lib/languages/cpp"
import csharp from "highlight.js/lib/languages/csharp"
import php from "highlight.js/lib/languages/php"
import swift from "highlight.js/lib/languages/swift"
import kotlin from "highlight.js/lib/languages/kotlin"
import xml from "highlight.js/lib/languages/xml"
import css from "highlight.js/lib/languages/css"
import scss from "highlight.js/lib/languages/scss"
import json from "highlight.js/lib/languages/json"
import yaml from "highlight.js/lib/languages/yaml"
import sql from "highlight.js/lib/languages/sql"
import graphql from "highlight.js/lib/languages/graphql"
import bash from "highlight.js/lib/languages/bash"
import shell from "highlight.js/lib/languages/shell"
import dockerfile from "highlight.js/lib/languages/dockerfile"
import diff from "highlight.js/lib/languages/diff"
import markdown from "highlight.js/lib/languages/markdown"
import plaintext from "highlight.js/lib/languages/plaintext"

const lowlight = createLowlight()
lowlight.register("javascript", javascript)
lowlight.register("typescript", typescript)
lowlight.register("python", python)
lowlight.register("elixir", elixir)
lowlight.register("ruby", ruby)
lowlight.register("go", go)
lowlight.register("rust", rust)
lowlight.register("java", java)
lowlight.register("c", c)
lowlight.register("cpp", cpp)
lowlight.register("csharp", csharp)
lowlight.register("php", php)
lowlight.register("swift", swift)
lowlight.register("kotlin", kotlin)
lowlight.register("html", xml)
lowlight.register("xml", xml)
lowlight.register("css", css)
lowlight.register("scss", scss)
lowlight.register("json", json)
lowlight.register("yaml", yaml)
lowlight.register("sql", sql)
lowlight.register("graphql", graphql)
lowlight.register("bash", bash)
lowlight.register("shell", shell)
lowlight.register("dockerfile", dockerfile)
lowlight.register("diff", diff)
lowlight.register("markdown", markdown)
lowlight.register("plaintext", plaintext)

// ── Bubble Menu ─────────────────────────────────────────────

const BUBBLE_BUTTONS = [
  { label: "B", action: "bold", style: "font-weight:700", title: "Bold (Cmd+B)" },
  { label: "I", action: "italic", style: "font-style:italic", title: "Italic (Cmd+I)" },
  { label: "U", action: "underline", style: "text-decoration:underline", title: "Underline (Cmd+U)" },
  { label: "S", action: "strike", style: "text-decoration:line-through", title: "Strikethrough (Cmd+Shift+S)" },
  { label: "`", action: "code", style: "font-family:monospace", title: "Inline Code (Cmd+E)" },
  { label: "H", action: "highlight", style: "background:#fef08a;color:#000;border-radius:2px", title: "Highlight (Cmd+Shift+H)" },
  { label: "🔗", action: "link", style: "", title: "Link (Cmd+K)" },
  { label: "x₂", action: "subscript", style: "font-size:0.7em", title: "Subscript" },
  { label: "x²", action: "superscript", style: "font-size:0.7em", title: "Superscript" },
]

function createBubbleMenuEl() {
  const menu = document.createElement("div")
  menu.className = "tiptap-bubble-menu"

  BUBBLE_BUTTONS.forEach(({ label, action, style, title }) => {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.textContent = label
    btn.dataset.action = action
    btn.title = title
    if (style) btn.style.cssText = style
    menu.appendChild(btn)
  })

  // Alignment group separator + buttons
  const sep = document.createElement("span")
  sep.className = "tiptap-bubble-sep"
  menu.appendChild(sep)

  const alignButtons = [
    { label: "⬅", action: "align-left", title: "Align Left" },
    { label: "⬌", action: "align-center", title: "Align Center" },
    { label: "➡", action: "align-right", title: "Align Right" },
  ]

  alignButtons.forEach(({ label, action, title }) => {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.textContent = label
    btn.dataset.action = action
    btn.title = title
    btn.style.cssText = "font-size:0.65em"
    menu.appendChild(btn)
  })

  return menu
}

function wireBubbleMenuButtons(menu, editor) {
  menu.querySelectorAll("button[data-action]").forEach((btn) => {
    const action = btn.dataset.action
    btn.addEventListener("mousedown", (e) => {
      // mousedown instead of click to prevent editor blur
      e.preventDefault()
      handleBubbleAction(editor, action)
    })
  })

  editor.on("selectionUpdate", () => updateBubbleActiveState(menu, editor))
  editor.on("transaction", () => updateBubbleActiveState(menu, editor))
}

function handleBubbleAction(editor, action) {
  switch (action) {
    case "bold":
      editor.chain().focus().toggleBold().run()
      break
    case "italic":
      editor.chain().focus().toggleItalic().run()
      break
    case "underline":
      editor.chain().focus().toggleUnderline().run()
      break
    case "strike":
      editor.chain().focus().toggleStrike().run()
      break
    case "code":
      editor.chain().focus().toggleCode().run()
      break
    case "highlight":
      editor.chain().focus().toggleHighlight().run()
      break
    case "subscript":
      editor.chain().focus().toggleSubscript().run()
      break
    case "superscript":
      editor.chain().focus().toggleSuperscript().run()
      break
    case "link":
      promptForLink(editor)
      break
    case "align-left":
      editor.chain().focus().setTextAlign("left").run()
      break
    case "align-center":
      editor.chain().focus().setTextAlign("center").run()
      break
    case "align-right":
      editor.chain().focus().setTextAlign("right").run()
      break
  }
}

function promptForLink(editor) {
  if (editor.isActive("link")) {
    editor.chain().focus().unsetLink().run()
    return
  }

  // Store selection before prompt steals focus
  const { from, to } = editor.state.selection
  const url = window.prompt("URL:")

  if (url) {
    editor
      .chain()
      .focus()
      .setTextSelection({ from, to })
      .setLink({ href: url, target: "_blank" })
      .run()
  } else {
    editor.chain().focus().run()
  }
}

function updateBubbleActiveState(menu, editor) {
  menu.querySelectorAll("button[data-action]").forEach((btn) => {
    const action = btn.dataset.action
    let isActive = false

    if (action === "align-left") isActive = editor.isActive({ textAlign: "left" })
    else if (action === "align-center") isActive = editor.isActive({ textAlign: "center" })
    else if (action === "align-right") isActive = editor.isActive({ textAlign: "right" })
    else isActive = editor.isActive(action)

    btn.classList.toggle("is-active", isActive)
  })
}

// ── Editor Hook ─────────────────────────────────────────────

const TiptapEditor = {
  mounted() {
    const content = this.el.dataset.value || ""
    const readOnly = this.el.dataset.readonly === "true"
    const eventName = this.el.dataset.event
    const fieldName = this.el.dataset.field
    const placeholder = this.el.dataset.placeholder || "Type '/' for commands..."

    const bubbleMenuEl = createBubbleMenuEl()
    this.el.appendChild(bubbleMenuEl)

    // Store pushEvent reference for keyboard shortcut save
    const pushEvent = eventName
      ? (payload) => this.pushEvent(eventName, payload)
      : null

    const extensions = [
      StarterKit.configure({ codeBlock: false }),
      Markdown.configure({
        html: true,
        tightLists: true,
        transformPastedText: true,
        transformCopiedText: true,
      }),
      Placeholder.configure({ placeholder }),
      Typography,
      TaskList,
      TaskItem.configure({ nested: true }),
      CodeBlockWithLang.configure({
        lowlight,
        defaultLanguage: "plaintext",
      }),

      // Links — no open on click in editor, auto-detect on paste
      Link.configure({
        openOnClick: false,
        autolink: true,
        linkOnPaste: true,
        defaultProtocol: "https",
        HTMLAttributes: {
          class: "text-primary underline cursor-pointer",
          rel: "noopener noreferrer",
          target: "_blank",
        },
      }),

      // Images — URL-based only, no base64 to avoid bloating markdown
      Image.configure({ inline: false, allowBase64: false }),

      // Text formatting marks
      Highlight.configure({ multicolor: false }),
      Underline,
      Subscript,
      Superscript,
      TextStyle,
      Color,

      // Text alignment
      TextAlign.configure({ types: ["heading", "paragraph"] }),

      // Tables
      Table.configure({ resizable: true }),
      TableRow,
      TableCell,
      TableHeader,

      // Character count (1MB, matches server-side validation)
      CharacterCount.configure({ limit: 1048576 }),

      // Menus
      BubbleMenu.configure({
        element: bubbleMenuEl,
        shouldShow: ({ editor, state }) => {
          // Don't show in code blocks, on images, or when selecting table cells
          if (editor.isActive("codeBlock") || editor.isActive("image")) return false
          return !state.selection.empty
        },
      }),
      SlashCommands.configure({
        suggestion: createSlashSuggestion(),
      }),
    ]

    this.editor = new Editor({
      element: this.el,
      extensions,
      content,
      editable: !readOnly,
      editorProps: {
        attributes: {
          class: "tiptap focus:outline-none",
        },
        // Cmd+S: save, Cmd+K: link
        handleKeyDown: (view, event) => {
          const isMod = event.metaKey || event.ctrlKey

          // Cmd+S — force immediate save
          if (isMod && event.key === "s") {
            event.preventDefault()
            if (pushEvent) {
              clearTimeout(this._debounce)
              const md = this.editor.storage.markdown.getMarkdown()
              const payload = fieldName
                ? { field: fieldName, value: md }
                : { value: md }
              pushEvent(payload)
            }
            return true
          }

          // Cmd+K — insert/toggle link
          if (isMod && event.key === "k") {
            event.preventDefault()
            promptForLink(this.editor)
            return true
          }

          return false
        },
      },
      onUpdate: ({ editor }) => {
        if (!eventName) return
        clearTimeout(this._debounce)
        this._debounce = setTimeout(() => {
          this._pushingUpdate = true
          const md = editor.storage.markdown.getMarkdown()
          const payload = fieldName
            ? { field: fieldName, value: md }
            : { value: md }
          this.pushEvent(eventName, payload)
        }, 500)
      },
    })

    wireBubbleMenuButtons(bubbleMenuEl, this.editor)
  },

  updated() {
    // Skip if this update was triggered by our own pushEvent — avoids
    // infinite loop where setContent() recreates NodeViews (mermaid etc.)
    // which triggers onUpdate → pushEvent → updated() → setContent() again.
    if (this._pushingUpdate) {
      this._pushingUpdate = false
      return
    }
    const newValue = this.el.dataset.value
    if (newValue !== undefined && this.editor) {
      const current = this.editor.storage.markdown.getMarkdown()
      if (newValue !== current) {
        this.editor.commands.setContent(newValue)
      }
    }
  },

  destroyed() {
    clearTimeout(this._debounce)
    if (this.editor) {
      this.editor.destroy()
      this.editor = null
    }
  },
}

export default TiptapEditor
