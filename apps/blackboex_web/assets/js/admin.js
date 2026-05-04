import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { Hooks as BackpexHooks } from "backpex";
import topbar from "../vendor/topbar";
import { buildLiveSocket } from "./lib/bootstrap/live_socket";
import { installTopbar } from "./lib/bootstrap/topbar";

const liveSocket = buildLiveSocket(LiveSocket, Socket, BackpexHooks);

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
