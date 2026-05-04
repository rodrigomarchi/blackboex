/**
 * @file Shared JavaScript library helpers for tiptap behavior.
 */
import { Extension } from "@tiptap/core";
import Suggestion from "@tiptap/suggestion";

/**
 * Provides commands.
 */
/**
 * Provides commands.
 */
export const COMMANDS = [
  // ── Text ──────────────────────────────────────────────────
  {
    title: "Text",
    description: "Plain paragraph text",
    icon: "Aa",
    category: "basic",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).setParagraph().run(),
  },
  {
    title: "Heading 1",
    description: "Large section heading",
    icon: "H1",
    category: "basic",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).setHeading({ level: 1 }).run(),
  },
  {
    title: "Heading 2",
    description: "Medium section heading",
    icon: "H2",
    category: "basic",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).setHeading({ level: 2 }).run(),
  },
  {
    title: "Heading 3",
    description: "Small section heading",
    icon: "H3",
    category: "basic",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).setHeading({ level: 3 }).run(),
  },

  // ── Lists ─────────────────────────────────────────────────
  {
    title: "Bullet List",
    description: "Unordered list of items",
    icon: "•",
    category: "lists",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).toggleBulletList().run(),
  },
  {
    title: "Numbered List",
    description: "Ordered list of items",
    icon: "1.",
    category: "lists",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).toggleOrderedList().run(),
  },
  {
    title: "Task List",
    description: "Checklist with checkboxes",
    icon: "☐",
    category: "lists",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).toggleTaskList().run(),
  },

  // ── Rich Blocks ───────────────────────────────────────────
  {
    title: "Code Block",
    description: "Syntax highlighted code",
    icon: "</>",
    category: "blocks",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).toggleCodeBlock().run(),
  },
  {
    title: "Blockquote",
    description: "Quoted text block",
    icon: "❝",
    category: "blocks",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).toggleBlockquote().run(),
  },
  {
    title: "Divider",
    description: "Horizontal separator line",
    icon: "—",
    category: "blocks",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).setHorizontalRule().run(),
  },

  // ── Table ─────────────────────────────────────────────────
  {
    title: "Table",
    description: "Insert a 3x3 table",
    icon: "⊞",
    category: "blocks",
    command: ({ editor, range }) =>
      editor
        .chain()
        .focus()
        .deleteRange(range)
        .insertTable({ rows: 3, cols: 3, withHeaderRow: true })
        .run(),
  },

  // ── Media ─────────────────────────────────────────────────
  {
    title: "Image",
    description: "Embed an image from URL",
    icon: "🖼",
    category: "media",
    command: ({ editor, range }) => {
      const url = window.prompt("Image URL:");
      if (url) {
        editor.chain().focus().deleteRange(range).setImage({ src: url }).run();
      }
    },
  },

  // ── Diagrams ───────────────────────────────────────────────
  {
    title: "Mermaid Diagram",
    description: "Flowchart, sequence, class diagram",
    icon: "◇",
    category: "blocks",
    command: ({ editor, range }) =>
      editor
        .chain()
        .focus()
        .deleteRange(range)
        .setCodeBlock({ language: "mermaid" })
        .insertContent(
          "graph TD\n  A[Start] --> B{Decision}\n  B -- Yes --> C[Done]\n  B -- No --> A",
        )
        .run(),
  },

  // ── Inline Formatting ─────────────────────────────────────
  {
    title: "Highlight",
    description: "Highlight selected text",
    icon: "🖍",
    category: "inline",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).toggleHighlight().run(),
  },

  // ── Alignment ─────────────────────────────────────────────
  {
    title: "Align Left",
    description: "Left-align text",
    icon: "⬅",
    category: "alignment",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).setTextAlign("left").run(),
  },
  {
    title: "Align Center",
    description: "Center-align text",
    icon: "⬌",
    category: "alignment",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).setTextAlign("center").run(),
  },
  {
    title: "Align Right",
    description: "Right-align text",
    icon: "➡",
    category: "alignment",
    command: ({ editor, range }) =>
      editor.chain().focus().deleteRange(range).setTextAlign("right").run(),
  },
];

const SlashCommands = Extension.create({
  name: "slashCommands",

  addOptions() {
    return { suggestion: {} };
  },

  addProseMirrorPlugins() {
    return [
      Suggestion({
        editor: this.editor,
        ...this.options.suggestion,
      }),
    ];
  },
});

/**
 * Provides create slash suggestion.
 * @returns {unknown} Function result.
 */
/**
 * Provides create slash suggestion.
 * @returns {unknown} Function result.
 */
function createSlashSuggestion() {
  let menuEl = null;
  let selectedIndex = 0;
  let items = [];

  function updateMenu() {
    if (!menuEl) return;
    menuEl.innerHTML = "";
    items.forEach((item, index) => {
      const div = document.createElement("div");
      div.className = `slash-item${index === selectedIndex ? " is-selected" : ""}`;
      div.innerHTML = `
        <span class="slash-item-icon">${item.icon}</span>
        <div class="slash-item-text">
          <span class="slash-item-title">${item.title}</span>
          <span class="slash-item-desc">${item.description}</span>
        </div>
      `;
      div.addEventListener("mouseenter", () => {
        selectedIndex = index;
        updateMenu();
      });
      div.addEventListener("mousedown", (e) => {
        // mousedown to prevent editor blur before command executes
        e.preventDefault();
        selectItem(index);
      });
      menuEl.appendChild(div);
    });

    // Scroll selected item into view
    const selected = menuEl.querySelector(".slash-item.is-selected");
    if (selected) selected.scrollIntoView({ block: "nearest" });
  }

  function selectItem(index) {
    const item = items[index];
    if (item && item._props) {
      item.command({ editor: item._props.editor, range: item._props.range });
    }
  }

  return {
    char: "/",
    allowSpaces: false,
    startOfLine: false,

    items: ({ query }) => {
      if (!query) return COMMANDS;
      const q = query.toLowerCase();
      return COMMANDS.filter(
        (cmd) =>
          cmd.title.toLowerCase().includes(q) ||
          cmd.description.toLowerCase().includes(q) ||
          cmd.category.toLowerCase().includes(q),
      );
    },

    render: () => ({
      onStart(props) {
        menuEl = document.createElement("div");
        menuEl.className = "slash-command-menu";
        selectedIndex = 0;
        items = props.items.map((i) => ({ ...i, _props: props }));
        updateMenu();

        const { view } = props.editor;
        const coords = view.coordsAtPos(props.range.from);

        menuEl.style.position = "fixed";
        menuEl.style.left = `${coords.left}px`;
        menuEl.style.top = `${coords.bottom + 4}px`;
        document.body.appendChild(menuEl);
      },

      onUpdate(props) {
        selectedIndex = 0;
        items = props.items.map((i) => ({ ...i, _props: props }));
        updateMenu();

        const { view } = props.editor;
        const coords = view.coordsAtPos(props.range.from);
        if (menuEl) {
          menuEl.style.left = `${coords.left}px`;
          menuEl.style.top = `${coords.bottom + 4}px`;
        }
      },

      onKeyDown({ event }) {
        if (event.key === "ArrowDown") {
          selectedIndex = (selectedIndex + 1) % items.length;
          updateMenu();
          return true;
        }
        if (event.key === "ArrowUp") {
          selectedIndex = (selectedIndex - 1 + items.length) % items.length;
          updateMenu();
          return true;
        }
        if (event.key === "Enter") {
          selectItem(selectedIndex);
          return true;
        }
        if (event.key === "Escape") {
          if (menuEl) {
            menuEl.remove();
            menuEl = null;
          }
          return true;
        }
        return false;
      },

      onExit() {
        if (menuEl) {
          menuEl.remove();
          menuEl = null;
        }
      },
    }),
  };
}

export { SlashCommands, createSlashSuggestion };
