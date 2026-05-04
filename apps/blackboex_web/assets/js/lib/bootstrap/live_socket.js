export function csrfToken(doc = document) {
  return doc.querySelector("meta[name='csrf-token']")?.getAttribute("content");
}

export function buildLiveSocket(LiveSocket, Socket, hooks, opts = {}) {
  return new LiveSocket(opts.path || "/live", Socket, {
    longPollFallbackMs: 2500,
    params: opts.params || {
      _csrf_token: csrfToken(opts.document || document),
    },
    hooks,
  });
}
