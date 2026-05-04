export function tiptapDatasetOptions(el) {
  return {
    content: el.dataset.value || "",
    readOnly: el.dataset.readonly === "true",
    eventName: el.dataset.event,
    fieldName: el.dataset.field,
    placeholder: el.dataset.placeholder || "Type '/' for commands...",
  };
}
