/**
 * @file Topbar progress integration for Phoenix page loading events.
 */
/**
 * Wires Phoenix page-loading events to topbar show/hide calls.
 * @param {{config: Function, show: Function, hide: Function}} topbar - Topbar adapter.
 * @param {Window | EventTarget} [target=window] - Event target receiving Phoenix loading events.
 * @param {object} [config={}] - Topbar configuration passed through unchanged.
 * @returns {() => void} Cleanup function that removes both event listeners.
 */
export function installTopbar(topbar, target = window, config = {}) {
  topbar.config(config);

  const show = () => topbar.show(300);
  const hide = () => topbar.hide();
  target.addEventListener("phx:page-loading-start", show);
  target.addEventListener("phx:page-loading-stop", hide);

  return () => {
    target.removeEventListener("phx:page-loading-start", show);
    target.removeEventListener("phx:page-loading-stop", hide);
  };
}
