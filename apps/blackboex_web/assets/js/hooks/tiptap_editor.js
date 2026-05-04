import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { Markdown } from "tiptap-markdown";
import Placeholder from "@tiptap/extension-placeholder";
import Typography from "@tiptap/extension-typography";
import TaskList from "@tiptap/extension-task-list";
import TaskItem from "@tiptap/extension-task-item";
// CodeBlockLowlight imported via code_block_lang.js extension
import BubbleMenu from "@tiptap/extension-bubble-menu";
import Link from "@tiptap/extension-link";
import Image from "@tiptap/extension-image";
import Highlight from "@tiptap/extension-highlight";
import Underline from "@tiptap/extension-underline";
import Subscript from "@tiptap/extension-subscript";
import Superscript from "@tiptap/extension-superscript";
import Table from "@tiptap/extension-table";
import TableRow from "@tiptap/extension-table-row";
import TableCell from "@tiptap/extension-table-cell";
import TableHeader from "@tiptap/extension-table-header";
import TextAlign from "@tiptap/extension-text-align";
import TextStyle from "@tiptap/extension-text-style";
import Color from "@tiptap/extension-color";
import CharacterCount from "@tiptap/extension-character-count";
import { SlashCommands, createSlashSuggestion } from "../lib/slash_commands";
import { CodeBlockWithLang } from "../lib/code_block_lang";
import {
  createBubbleMenuEl,
  promptForLink,
  wireBubbleMenuButtons,
} from "../lib/tiptap/bubble_menu";
import { tiptapDatasetOptions } from "../lib/tiptap/editor_options";
import { buildLowlight } from "../lib/tiptap/lowlight_languages";
import {
  markdownPayload,
  syncMarkdownContent,
} from "../lib/tiptap/markdown_sync";

const lowlight = buildLowlight();

// ── Editor Hook ─────────────────────────────────────────────

const TiptapEditor = {
  mounted() {
    const { content, readOnly, eventName, fieldName, placeholder } =
      tiptapDatasetOptions(this.el);

    const bubbleMenuEl = createBubbleMenuEl();
    this.el.appendChild(bubbleMenuEl);

    // Store pushEvent reference for keyboard shortcut save
    const pushEvent = eventName
      ? (payload) => this.pushEvent(eventName, payload)
      : null;

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
          if (editor.isActive("codeBlock") || editor.isActive("image")) {
            return false;
          }
          return !state.selection.empty;
        },
      }),
      SlashCommands.configure({
        suggestion: createSlashSuggestion(),
      }),
    ];

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
          const isMod = event.metaKey || event.ctrlKey;

          // Cmd+S — force immediate save
          if (isMod && event.key === "s") {
            event.preventDefault();
            if (pushEvent) {
              clearTimeout(this._debounce);
              pushEvent(markdownPayload(this.editor, fieldName));
            }
            return true;
          }

          // Cmd+K — insert/toggle link
          if (isMod && event.key === "k") {
            event.preventDefault();
            promptForLink(this.editor);
            return true;
          }

          return false;
        },
      },
      onUpdate: ({ editor }) => {
        if (!eventName) return;
        // Skip when the change came from a programmatic setContent we just
        // applied (server pushed new markdown via data-value). Without this
        // guard the editor would push the AI-produced content back to the
        // server as if the user typed it, racing with — and potentially
        // overwriting — the user's actual keystrokes that arrived first.
        if (this._suppressNextOnUpdate) {
          this._suppressNextOnUpdate = false;
          return;
        }
        clearTimeout(this._debounce);
        this._debounce = setTimeout(() => {
          this._pushingUpdate = true;
          this.pushEvent(eventName, markdownPayload(editor, fieldName));
        }, 500);
      },
    });

    wireBubbleMenuButtons(bubbleMenuEl, this.editor);
  },

  updated() {
    // Skip if this update was triggered by our own pushEvent — avoids
    // infinite loop where setContent() recreates NodeViews (mermaid etc.)
    // which triggers onUpdate → pushEvent → updated() → setContent() again.
    if (this._pushingUpdate) {
      this._pushingUpdate = false;
      return;
    }
    const newValue = this.el.dataset.value;
    if (newValue !== undefined && this.editor) {
      if (newValue !== this.editor.storage.markdown.getMarkdown()) {
        // Mark the next onUpdate as caused by us, not by user typing.
        this._suppressNextOnUpdate = true;
        syncMarkdownContent(this.editor, newValue);
      }
    }
  },

  destroyed() {
    clearTimeout(this._debounce);
    if (this.editor) {
      this.editor.destroy();
      this.editor = null;
    }
  },
};

export default TiptapEditor;
