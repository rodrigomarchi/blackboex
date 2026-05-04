/**
 * @file Global LiveView hook that focuses an element after LiveView patches.
 */
/**
 * Focuses the mounted element and refocuses it after updates.
 */
const AutoFocus = {
  mounted() {
    this.el.focus();
  },

  updated() {
    this.el.focus();
  },
};

/**
 * Focus helper hook registered as `AutoFocus`.
 */
export default AutoFocus;
