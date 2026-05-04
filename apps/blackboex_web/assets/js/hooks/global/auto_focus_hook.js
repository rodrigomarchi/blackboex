/**
 * @file Global LiveView hook wiring for auto focus hook behavior.
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
 * Exports the module default value.
 */
export default AutoFocus;
