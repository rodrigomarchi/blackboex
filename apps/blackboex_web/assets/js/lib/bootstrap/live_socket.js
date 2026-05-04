/**
 * @file Shared JavaScript library helpers for bootstrap behavior.
 */
/**
 * Provides csrf token.
 * @param {unknown} doc - Document used for DOM lookup.
 * @returns {unknown} Function result.
 */
export function csrfToken(doc = document) {
  return doc.querySelector("meta[name='csrf-token']")?.getAttribute("content");
}

/**
 * Provides build live socket.
 * @param {unknown} LiveSocket - LiveSocket value.
 * @param {unknown} Socket - Socket value.
 * @param {unknown} hooks - hooks value.
 * @param {unknown} opts - Optional configuration values.
 * @returns {unknown} Function result.
 */
export function buildLiveSocket(LiveSocket, Socket, hooks, opts = {}) {
  return new LiveSocket(opts.path || "/live", Socket, {
    longPollFallbackMs: 2500,
    params: opts.params || {
      _csrf_token: csrfToken(opts.document || document),
    },
    hooks,
  });
}
