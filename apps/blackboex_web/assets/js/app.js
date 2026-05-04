import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/blackboex_web";
import { Hooks as BackpexHooks } from "backpex";
import topbar from "../vendor/topbar";

import AutoFocus from "./hooks/global/auto_focus_hook";
import ChatAutoScroll from "./hooks/global/chat_auto_scroll_hook";
import CommandPaletteNav from "./hooks/global/command_palette_nav_hook";
import EditorAutoScroll from "./hooks/global/editor_auto_scroll_hook";
import KeyboardShortcuts from "./hooks/global/keyboard_shortcuts_hook";
import SidebarCollapse from "./hooks/global/sidebar_collapse_hook";
import ResizablePanels from "./hooks/resizable_panels";
import SidebarTreeDnD from "./hooks/sidebar_tree_dnd";
import { installClipboardHandler } from "./lib/browser/clipboard";
import { installDownloadFileHandler } from "./lib/browser/download_file";
import { lazyHook } from "./lib/bootstrap/lazy_hook";
import { buildLiveSocket } from "./lib/bootstrap/live_socket";
import { installTopbar } from "./lib/bootstrap/topbar";

const hooks = {
  ...colocatedHooks,
  CodeEditor: lazyHook(() => import("./hooks/code_editor")),
  DrawflowEditor: lazyHook(() => import("./hooks/drawflow_editor")),
  KeyboardShortcuts,
  AutoFocus,
  ChatAutoScroll,
  EditorAutoScroll,
  CommandPaletteNav,
  PlaygroundEditor: lazyHook(() => import("./hooks/playground_editor")),
  ResizablePanels,
  SidebarTreeDnD,
  SidebarCollapse,
  TiptapEditor: lazyHook(() => import("./hooks/tiptap_editor")),
  ...BackpexHooks,
};

const liveSocket = buildLiveSocket(LiveSocket, Socket, hooks);

installTopbar(topbar, window, {
  barColors: { 0: "#29d" },
  shadowColor: "rgba(0, 0, 0, .3)",
});
installClipboardHandler(window);
installDownloadFileHandler(window);

liveSocket.connect();
window.liveSocket = liveSocket;

if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      reloader.enableServerLogs();

      let keyDown;
      window.addEventListener("keydown", (event) => (keyDown = event.key));
      window.addEventListener("keyup", (_event) => (keyDown = null));
      window.addEventListener(
        "click",
        (event) => {
          if (keyDown === "c") {
            event.preventDefault();
            event.stopImmediatePropagation();
            reloader.openEditorAtCaller(event.target);
          } else if (keyDown === "d") {
            event.preventDefault();
            event.stopImmediatePropagation();
            reloader.openEditorAtDef(event.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
