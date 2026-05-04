/**
 * @file DOM scroll helpers shared by chat and editor LiveView hooks.
 */
/**
 * Checks whether a scroll container is near its bottom edge.
 * @param {Element} el - Scroll container.
 * @param {number} [threshold=80] - Pixel tolerance before treating the user as scrolled up.
 * @returns {boolean} True when the scroll offset is within the threshold.
 */
export function isAtBottom(el, threshold = 80) {
  return el.scrollHeight - el.scrollTop - el.clientHeight < threshold;
}

/**
 * Moves a scroll container to its maximum vertical scroll offset.
 * @param {Element} el - Scroll container to mutate.
 * @returns {void}
 */
export function scrollElementToBottom(el) {
  el.scrollTop = el.scrollHeight;
}

/**
 * Scrolls the chat root and nested scroll panes to latest content.
 * @param {Element} el - Chat root element.
 * @returns {void}
 */
export function scrollChatToBottom(el) {
  scrollElementToBottom(el);
  el.querySelectorAll(".overflow-y-auto").forEach((inner) =>
    scrollElementToBottom(inner),
  );
}

/**
 * Finds the primary nested editor scroll pane inside a hook root.
 * @param {ParentNode} root - Hook root or document to search.
 * @returns {Element | null} First nested overflow container.
 */
export function findEditorScroller(root) {
  return root.querySelector(".overflow-y-auto");
}
