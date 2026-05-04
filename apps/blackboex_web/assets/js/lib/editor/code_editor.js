export function buildCodeEditorOptions(el) {
  return {
    language: el.dataset.language || "text",
    readOnly: el.dataset.readonly === "true",
    minimal: el.dataset.minimal === "true",
    eventName: el.dataset.event,
    fieldName: el.dataset.field,
    initialValue: el.dataset.value || "",
  };
}

export function buildBlurHandler(hook, { readOnly, eventName, fieldName }) {
  if (readOnly || !eventName) return null;

  return (_event, view) => {
    const value = view.state.doc.toString();
    const payload = fieldName ? { field: fieldName, value } : { value };
    hook.pushEvent(eventName, payload);
  };
}

export function shouldSyncDocument(newValue, currentValue) {
  return newValue !== undefined && newValue !== currentValue;
}

export function syncCodeMirrorDocument(view, newValue) {
  if (!view) return false;
  const currentValue = view.state.doc.toString();
  if (!shouldSyncDocument(newValue, currentValue)) return false;

  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: newValue },
  });
  return true;
}
