/**
 * @file Backpex admin Phoenix LiveView browser entrypoint.
 *
 * Uses the same LiveSocket/bootstrap helpers as the public app but registers
 * only Backpex hooks plus the lazy CodeEditor needed by admin form fields.
 */
import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { Hooks as BackpexHooks } from "backpex";
import topbar from "../vendor/topbar";
import { buildAdminHooks } from "./lib/bootstrap/hook_maps";
import { lazyHook } from "./lib/bootstrap/lazy_hook";
import { buildLiveSocket } from "./lib/bootstrap/live_socket";
import { installTopbar } from "./lib/bootstrap/topbar";

const hooks = buildAdminHooks({
  codeEditor: lazyHook(() => import("./hooks/code_editor")),
  backpexHooks: BackpexHooks,
});

const liveSocket = buildLiveSocket(LiveSocket, Socket, hooks);

installTopbar(topbar, window, {
  barColors: { 0: "#29d" },
  shadowColor: "rgba(0, 0, 0, .3)",
});

liveSocket.connect();
window.liveSocket = liveSocket;

if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      reloader.enableServerLogs();
      window.liveReloader = reloader;
    },
  );
}
