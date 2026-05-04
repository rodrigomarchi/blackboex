/**
 * @file Global LiveView hook wiring for chat auto scroll hook behavior.
 */
import { isAtBottom, scrollChatToBottom } from "../../lib/global/auto_scroll";

/**
 * LiveView hook for chat auto scroll behavior.
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
 * Exports the module default value.
 */
export default ChatAutoScroll;
