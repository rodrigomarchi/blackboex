/**
 * @file Builds and wires the floating Tiptap formatting bubble menu.
 */
/**
 * Inline mark buttons shown when the user selects editable rich text.
 */
export const BUBBLE_BUTTONS = [
  {
    label: "B",
    action: "bold",
    style: "font-weight:700",
    title: "Bold (Cmd+B)",
  },
  {
    label: "I",
    action: "italic",
    style: "font-style:italic",
    title: "Italic (Cmd+I)",
  },
  {
    label: "U",
    action: "underline",
    style: "text-decoration:underline",
    title: "Underline (Cmd+U)",
  },
  {
    label: "S",
    action: "strike",
    style: "text-decoration:line-through",
    title: "Strikethrough (Cmd+Shift+S)",
  },
  {
    label: "`",
    action: "code",
    style: "font-family:monospace",
    title: "Inline Code (Cmd+E)",
  },
  {
    label: "H",
    action: "highlight",
    style: "background:#fef08a;color:#000;border-radius:2px",
    title: "Highlight (Cmd+Shift+H)",
  },
  { label: "🔗", action: "link", style: "", title: "Link (Cmd+K)" },
  {
    label: "x₂",
    action: "subscript",
    style: "font-size:0.7em",
    title: "Subscript",
  },
  {
    label: "x²",
    action: "superscript",
    style: "font-size:0.7em",
    title: "Superscript",
  },
];

/**
 * Text alignment buttons appended after the mark controls.
 */
const ALIGN_BUTTONS = [
  { label: "⬅", action: "align-left", title: "Align Left" },
  { label: "⬌", action: "align-center", title: "Align Center" },
  { label: "➡", action: "align-right", title: "Align Right" },
];

/**
 * Creates the DOM element passed to Tiptap's BubbleMenu extension.
 * @param {Document} doc - Document used to create menu elements.
 * @returns {HTMLDivElement} Detached bubble menu element.
 */
export function createBubbleMenuEl(doc = document) {
  const menu = doc.createElement("div");
  menu.className = "tiptap-bubble-menu";

  BUBBLE_BUTTONS.forEach(({ label, action, style, title }) => {
    menu.appendChild(createBubbleButton(doc, { label, action, style, title }));
  });

  const sep = doc.createElement("span");
  sep.className = "tiptap-bubble-sep";
  menu.appendChild(sep);

  ALIGN_BUTTONS.forEach(({ label, action, title }) => {
    menu.appendChild(
      createBubbleButton(doc, {
        label,
        action,
        style: "font-size:0.65em",
        title,
      }),
    );
  });

  return menu;
}

/**
 * Creates a button with the dataset action consumed by `wireBubbleMenuButtons`.
 * @param {Document} doc - Document used to create the button.
 * @param {object} options - Button metadata.
 * @param {string} options.label - Visible button label.
 * @param {string} options.action - Formatting action stored in `data-action`.
 * @param {string} options.style - Optional inline style for compact icon-like labels.
 * @param {string} options.title - Browser tooltip text.
 * @returns {HTMLButtonElement} Configured toolbar button.
 */
function createBubbleButton(doc, { label, action, style, title }) {
  const button = doc.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.dataset.action = action;
  button.title = title;
  if (style) button.style.cssText = style;
  return button;
}

/**
 * Connects toolbar buttons to editor commands and keeps active state in sync.
 * @param {HTMLElement} menu - Bubble menu returned by `createBubbleMenuEl`.
 * @param {{on: Function}} editor - Tiptap editor instance.
 * @param {Function} prompt - Prompt implementation used by link insertion.
 * @returns {void}
 */
export function wireBubbleMenuButtons(menu, editor, prompt = window.prompt) {
  menu.querySelectorAll("button[data-action]").forEach((button) => {
    const action = button.dataset.action;
    button.addEventListener("mousedown", (event) => {
      event.preventDefault();
      handleBubbleAction(editor, action, prompt);
    });
  });

  editor.on("selectionUpdate", () => updateBubbleActiveState(menu, editor));
  editor.on("transaction", () => updateBubbleActiveState(menu, editor));
}

/**
 * Dispatches one bubble menu action to the corresponding Tiptap command chain.
 * @param {{chain: Function}} editor - Tiptap editor instance.
 * @param {string | undefined} action - Action read from the clicked button dataset.
 * @param {Function} prompt - Prompt implementation used by link insertion.
 * @returns {boolean} Tiptap command result, or false for unknown actions.
 */
export function handleBubbleAction(editor, action, prompt = window.prompt) {
  switch (action) {
    case "bold":
      return editor.chain().focus().toggleBold().run();
    case "italic":
      return editor.chain().focus().toggleItalic().run();
    case "underline":
      return editor.chain().focus().toggleUnderline().run();
    case "strike":
      return editor.chain().focus().toggleStrike().run();
    case "code":
      return editor.chain().focus().toggleCode().run();
    case "highlight":
      return editor.chain().focus().toggleHighlight().run();
    case "subscript":
      return editor.chain().focus().toggleSubscript().run();
    case "superscript":
      return editor.chain().focus().toggleSuperscript().run();
    case "link":
      return promptForLink(editor, prompt);
    case "align-left":
      return editor.chain().focus().setTextAlign("left").run();
    case "align-center":
      return editor.chain().focus().setTextAlign("center").run();
    case "align-right":
      return editor.chain().focus().setTextAlign("right").run();
    default:
      return false;
  }
}

/**
 * Toggles an active link off or prompts for a URL and applies it to the selection.
 * @param {{isActive: Function, state: {selection: {from: number, to: number}}, chain: Function}} editor - Tiptap editor instance.
 * @param {Function} prompt - Prompt implementation, injectable for tests.
 * @returns {boolean} Tiptap command result.
 */
export function promptForLink(editor, prompt = window.prompt) {
  if (editor.isActive("link")) {
    return editor.chain().focus().unsetLink().run();
  }

  const { from, to } = editor.state.selection;
  const url = prompt("URL:");

  if (url) {
    return editor
      .chain()
      .focus()
      .setTextSelection({ from, to })
      .setLink({ href: url, target: "_blank" })
      .run();
  }

  return editor.chain().focus().run();
}

/**
 * Reflects editor mark/alignment state onto toolbar button classes.
 * @param {HTMLElement} menu - Bubble menu containing `button[data-action]` elements.
 * @param {{isActive: Function}} editor - Tiptap editor instance.
 * @returns {void}
 */
export function updateBubbleActiveState(menu, editor) {
  menu.querySelectorAll("button[data-action]").forEach((button) => {
    const action = button.dataset.action;
    const isActive =
      action === "align-left"
        ? editor.isActive({ textAlign: "left" })
        : action === "align-center"
          ? editor.isActive({ textAlign: "center" })
          : action === "align-right"
            ? editor.isActive({ textAlign: "right" })
            : editor.isActive(action);

    button.classList.toggle("is-active", isActive);
  });
}
