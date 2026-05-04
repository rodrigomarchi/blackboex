/**
 * @file Compatibility re-export for the Tiptap code block language extension.
 *
 * Existing imports use `js/lib/code_block_lang`; the implementation lives under
 * `js/lib/tiptap/code_block_lang` with the rest of the rich editor modules.
 */
export {
  CodeBlockWithLang,
  LANG_LABELS,
  enqueueRender,
  fitSvg,
  getMermaid,
  setMermaidLoader,
} from "./tiptap/code_block_lang";
