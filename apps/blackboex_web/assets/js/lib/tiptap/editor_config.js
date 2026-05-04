import StarterKit from "@tiptap/starter-kit";
import { Markdown } from "tiptap-markdown";
import Placeholder from "@tiptap/extension-placeholder";
import Typography from "@tiptap/extension-typography";
import TaskList from "@tiptap/extension-task-list";
import TaskItem from "@tiptap/extension-task-item";
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
import { SlashCommands, createSlashSuggestion } from "../slash_commands";
import { CodeBlockWithLang } from "../code_block_lang";
import { promptForLink } from "./bubble_menu";
import { buildLowlight } from "./lowlight_languages";
import { markdownPayload } from "./markdown_sync";

const lowlight = buildLowlight();

export function shouldShowBubbleMenu({ editor, state }) {
  if (editor.isActive("codeBlock") || editor.isActive("image")) {
    return false;
  }
  return !state.selection.empty;
}

export function buildTiptapExtensions({ bubbleMenuEl, placeholder }) {
  return [
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
    Image.configure({ inline: false, allowBase64: false }),
    Highlight.configure({ multicolor: false }),
    Underline,
    Subscript,
    Superscript,
    TextStyle,
    Color,
    TextAlign.configure({ types: ["heading", "paragraph"] }),
    Table.configure({ resizable: true }),
    TableRow,
    TableCell,
    TableHeader,
    CharacterCount.configure({ limit: 1048576 }),
    BubbleMenu.configure({
      element: bubbleMenuEl,
      shouldShow: shouldShowBubbleMenu,
    }),
    SlashCommands.configure({
      suggestion: createSlashSuggestion(),
    }),
  ];
}

export function buildTiptapEditorProps({
  getEditor,
  fieldName,
  pushEvent,
  clearDebounce,
  promptForLinkFn = promptForLink,
}) {
  return {
    attributes: {
      class: "tiptap focus:outline-none",
    },
    handleKeyDown: (_view, event) => {
      const isMod = event.metaKey || event.ctrlKey;

      if (isMod && event.key === "s") {
        event.preventDefault();
        if (pushEvent) {
          clearDebounce();
          pushEvent(markdownPayload(getEditor(), fieldName));
        }
        return true;
      }

      if (isMod && event.key === "k") {
        event.preventDefault();
        promptForLinkFn(getEditor());
        return true;
      }

      return false;
    },
  };
}

export function buildTiptapOnUpdate({
  hook,
  eventName,
  fieldName,
  delay = 500,
}) {
  return ({ editor }) => {
    if (!eventName) return;
    if (hook._suppressNextOnUpdate) {
      hook._suppressNextOnUpdate = false;
      return;
    }

    clearTimeout(hook._debounce);
    hook._debounce = setTimeout(() => {
      hook._pushingUpdate = true;
      hook.pushEvent(eventName, markdownPayload(editor, fieldName));
    }, delay);
  };
}
