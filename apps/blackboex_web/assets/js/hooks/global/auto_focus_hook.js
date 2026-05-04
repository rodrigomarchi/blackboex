const AutoFocus = {
  mounted() {
    this.el.focus();
  },

  updated() {
    this.el.focus();
  },
};

export default AutoFocus;
