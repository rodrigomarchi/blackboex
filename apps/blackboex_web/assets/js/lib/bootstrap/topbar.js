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
