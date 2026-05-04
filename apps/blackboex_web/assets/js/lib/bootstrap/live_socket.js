/**
 * @file Phoenix LiveSocket construction helpers for browser entrypoints.
 */
/**
 * Reads the Phoenix CSRF token from the document meta tag.
 * @param {Document} [doc=document] - Document to inspect.
 * @returns {string | undefined} CSRF token when present.
 */
export function csrfToken(doc = document) {
  return doc.querySelector("meta[name='csrf-token']")?.getAttribute("content");
}

/**
 * Constructs a Phoenix LiveSocket with Blackboex defaults.
 * @param {new (path: string, socket: Function, options: object) => object} LiveSocket - Phoenix LiveSocket constructor.
 * @param {Function} Socket - Phoenix Socket constructor.
 * @param {object} hooks - Hook map registered with LiveSocket.
 * @param {{path?: string, params?: object, document?: Document}} [opts={}] - Testable construction overrides.
 * @returns {object} Configured LiveSocket instance.
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
