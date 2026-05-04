export function playgroundEventForKey(action) {
  return {
    run: "run",
    save: "save_code",
    format: "format_code",
  }[action];
}

export function replaceDocument(view, code) {
  if (!view || typeof code !== "string") return false;

  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: code },
  });
  return true;
}

export function resolveCompletionItems(state, items) {
  if (!state.completionResolve) return false;
  state.completionResolve(items);
  state.completionResolve = null;
  return true;
}

export function makeDebouncedCodeSync(hook, delay = 300) {
  let debounceTimer = null;
  return (update) => {
    if (!update.docChanged) return;

    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      hook.pushEvent("update_code", { value: update.state.doc.toString() });
    }, delay);
  };
}
