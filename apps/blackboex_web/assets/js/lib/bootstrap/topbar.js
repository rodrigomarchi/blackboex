/**
 * @file Shared JavaScript library helpers for bootstrap behavior.
 */
/**
 * Provides install topbar.
 * @param {unknown} topbar - topbar value.
 * @param {unknown} target - Target event source or DOM element.
 * @param {unknown} config - Configuration passed to the helper.
 * @returns {unknown} Function result.
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
