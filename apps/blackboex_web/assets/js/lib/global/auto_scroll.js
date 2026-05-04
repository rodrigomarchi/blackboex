/**
 * @file Shared JavaScript library helpers for global behavior.
 */
/**
 * Provides is at bottom.
 * @param {unknown} el - DOM element used by the helper.
 * @param {unknown} threshold - threshold value.
 * @returns {unknown} Function result.
 */
export function isAtBottom(el, threshold = 80) {
  return el.scrollHeight - el.scrollTop - el.clientHeight < threshold;
}

/**
 * Provides scroll element to bottom.
 * @param {unknown} el - DOM element used by the helper.
 * @returns {unknown} Function result.
 */
export function scrollElementToBottom(el) {
  el.scrollTop = el.scrollHeight;
}

/**
 * Provides scroll chat to bottom.
 * @param {unknown} el - DOM element used by the helper.
 * @returns {unknown} Function result.
 */
export function scrollChatToBottom(el) {
  scrollElementToBottom(el);
  el.querySelectorAll(".overflow-y-auto").forEach((inner) =>
    scrollElementToBottom(inner),
  );
}

/**
 * Provides find editor scroller.
 * @param {unknown} root - Root element or document used for lookup.
 * @returns {unknown} Function result.
 */
export function findEditorScroller(root) {
  return root.querySelector(".overflow-y-auto");
}
