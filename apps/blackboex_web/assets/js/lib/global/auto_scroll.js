export function isAtBottom(el, threshold = 80) {
  return el.scrollHeight - el.scrollTop - el.clientHeight < threshold;
}

export function scrollElementToBottom(el) {
  el.scrollTop = el.scrollHeight;
}

export function scrollChatToBottom(el) {
  scrollElementToBottom(el);
  el.querySelectorAll(".overflow-y-auto").forEach((inner) =>
    scrollElementToBottom(inner),
  );
}

export function findEditorScroller(root) {
  return root.querySelector(".overflow-y-auto");
}
