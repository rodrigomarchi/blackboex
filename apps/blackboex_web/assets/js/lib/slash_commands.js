/**
 * @file Compatibility re-export for the Tiptap slash command extension.
 *
 * Existing imports use `js/lib/slash_commands`; the implementation lives under
 * `js/lib/tiptap/slash_commands` with the rest of the rich editor modules.
 */
export {
  COMMANDS,
  SlashCommands,
  createSlashSuggestion,
} from "./tiptap/slash_commands";
