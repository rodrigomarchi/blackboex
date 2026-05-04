import { EditorView } from "@codemirror/view";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";

const theme = EditorView.theme(
  {
    "&": {
      backgroundColor: "hsl(var(--background))",
      color: "hsl(var(--foreground))",
      fontSize: "12px",
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, monospace",
      lineHeight: "1.6",
    },
    ".cm-content": {
      caretColor: "hsl(var(--primary))",
      padding: "8px 0",
    },
    ".cm-cursor, .cm-dropCursor": {
      borderLeftColor: "hsl(var(--primary))",
    },
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
      backgroundColor: "hsl(var(--accent))",
    },
    ".cm-activeLine": {
      backgroundColor: "hsl(var(--muted) / 0.15)",
    },
    ".cm-gutters": {
      backgroundColor: "hsl(var(--card))",
      color: "hsl(var(--muted-foreground))",
      borderRight: "1px solid hsl(var(--border))",
      fontSize: "11px",
    },
    ".cm-activeLineGutter": {
      backgroundColor: "hsl(var(--muted) / 0.15)",
    },
    "&.cm-focused": {
      outline: "none",
    },
    ".cm-scroller": {
      overflow: "auto",
    },
    ".cm-matchingBracket": {
      backgroundColor: "hsl(var(--accent))",
      outline: "1px solid hsl(var(--primary) / 0.5)",
    },
    ".cm-tooltip": {
      backgroundColor: "hsl(var(--card))",
      border: "1px solid hsl(var(--border))",
      color: "hsl(var(--foreground))",
    },
    ".cm-tooltip-autocomplete": {
      "& > ul > li[aria-selected]": {
        backgroundColor: "hsl(var(--accent))",
      },
    },
    ".cm-diagnostic-error": {
      borderBottom: "2px solid hsl(var(--destructive))",
    },
  },
  { dark: true },
);

const highlightStyle = HighlightStyle.define([
  { tag: tags.keyword, color: "#c678dd" },
  { tag: tags.operator, color: "#56b6c2" },
  { tag: tags.atom, color: "#d19a66" },
  { tag: tags.bool, color: "#d19a66" },
  { tag: tags.null, color: "#d19a66" },
  { tag: tags.number, color: "#d19a66" },
  { tag: tags.string, color: "#98c379" },
  { tag: tags.regexp, color: "#98c379" },
  { tag: tags.variableName, color: "#e06c75" },
  { tag: tags.function(tags.variableName), color: "#61afef" },
  { tag: tags.definition(tags.variableName), color: "#e5c07b" },
  { tag: tags.propertyName, color: "#61afef" },
  { tag: tags.comment, color: "#5c6370", fontStyle: "italic" },
  { tag: tags.meta, color: "#abb2bf" },
  { tag: tags.typeName, color: "#e5c07b" },
  { tag: tags.tagName, color: "#e06c75" },
  { tag: tags.attributeName, color: "#d19a66" },
  { tag: tags.punctuation, color: "#abb2bf" },
]);

export const blackboexEditorTheme = [theme, syntaxHighlighting(highlightStyle)];
