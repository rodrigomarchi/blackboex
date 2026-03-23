import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { Hooks as BackpexHooks } from "backpex"
import topbar from "../vendor/topbar"

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(250))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...BackpexHooks }
})

liveSocket.connect()

window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    reloader.enableServerLogs()
  })
}
