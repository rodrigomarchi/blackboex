/**
 * @file Global LiveView hook that keeps chat timelines pinned while streaming.
 */
import { isAtBottom, scrollChatToBottom } from "../../lib/global/auto_scroll";

/**
 * Maintains bottom scroll for chat streams until the user intentionally scrolls up.
 *
 * Uses MutationObserver for inserted nodes and a short poll for text patches
 * from LiveView streams that mutate existing nodes without adding children.
 */
const ChatAutoScroll = {
  mounted() {
    this._userScrolledUp = false;
    this._lastHeight = 0;
    this.scrollToBottom();

    this.observer = new MutationObserver(() => {
      if (!this._userScrolledUp) this.scrollToBottom();
    });
    this.observer.observe(this.el, {
      childList: true,
      subtree: true,
      characterData: true,
    });

    this._poll = setInterval(() => {
      if (this.el.scrollHeight !== this._lastHeight) {
        this._lastHeight = this.el.scrollHeight;
        if (!this._userScrolledUp) this.scrollToBottom();
      }
    }, 150);

    this.handleScroll = () => {
      this._userScrolledUp = !isAtBottom(this.el);
    };
    this.el.addEventListener("scroll", this.handleScroll);
  },

  updated() {
    if (!this._userScrolledUp) this.scrollToBottom();
  },

  destroyed() {
    if (this.observer) this.observer.disconnect();
    if (this._poll) clearInterval(this._poll);
    this.el.removeEventListener("scroll", this.handleScroll);
  },

  scrollToBottom() {
    requestAnimationFrame(() => scrollChatToBottom(this.el));
  },
};

/**
 * Chat timeline auto-scroll hook registered as `ChatAutoScroll`.
 */
export default ChatAutoScroll;
