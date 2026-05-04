/**
 * @file Global LiveView hook that follows streamed editor output.
 */
import {
  findEditorScroller,
  isAtBottom,
  scrollElementToBottom,
} from "../../lib/global/auto_scroll";

/**
 * Keeps the first `.overflow-y-auto` child pinned to bottom while AI output grows.
 *
 * The hook pauses after manual user scroll-up and resumes only when LiveView
 * patches arrive while the user remains at the bottom.
 */
const EditorAutoScroll = {
  mounted() {
    this._userScrolledUp = false;
    this._lastHeight = 0;

    this._poll = setInterval(() => {
      const scroller = this.getScroller();
      if (scroller && scroller.scrollHeight !== this._lastHeight) {
        this._lastHeight = scroller.scrollHeight;
        if (!this._userScrolledUp) this.scrollToBottom();
      }
    }, 150);

    this.handleScroll = (event) => {
      const scroller = event.target;
      if (scroller?.classList?.contains("overflow-y-auto")) {
        this._userScrolledUp = !isAtBottom(scroller);
      }
    };

    this.el.addEventListener("scroll", this.handleScroll, true);
  },

  updated() {
    if (!this._userScrolledUp) this.scrollToBottom();
  },

  destroyed() {
    if (this._poll) clearInterval(this._poll);
    this.el.removeEventListener("scroll", this.handleScroll, true);
  },

  getScroller() {
    return findEditorScroller(this.el);
  },

  scrollToBottom() {
    const scroller = this.getScroller();
    if (scroller) requestAnimationFrame(() => scrollElementToBottom(scroller));
  },
};

/**
 * Editor output auto-scroll hook registered as `EditorAutoScroll`.
 */
export default EditorAutoScroll;
