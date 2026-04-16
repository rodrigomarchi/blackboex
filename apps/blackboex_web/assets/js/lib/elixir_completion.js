/**
 * CodeMirror autocompletion source for Elixir, backed by server-side
 * module introspection via LiveView pushEvent with {:reply, ...}.
 */

/**
 * Creates a CodeMirror completion source wired to the PlaygroundEditor hook.
 * @param {object} hook - The LiveView hook instance (provides pushEvent)
 * @returns {function} CodeMirror completion source function
 */
export function elixirCompletionSource(hook) {
  return async (context) => {
    const word = context.matchBefore(/[\w.]+/)
    if (!word || word.from === word.to) return null

    const hint = word.text

    // Only trigger after a dot or with at least 2 chars
    if (!hint.includes(".") && hint.length < 2) return null

    const items = await new Promise((resolve) => {
      hook.pushEvent("autocomplete", { hint }, (reply) => {
        resolve(reply.items || [])
      })

      // Timeout fallback
      setTimeout(() => resolve([]), 2000)
    })

    if (!items || items.length === 0) return null

    // Calculate the "from" position for replacement.
    // If hint has a dot (e.g. "Enum.ma"), only replace after the dot.
    const dotIndex = hint.lastIndexOf(".")
    const from = dotIndex >= 0 ? word.from + dotIndex + 1 : word.from

    return {
      from,
      options: items.map((item) => {
        // Strip arity from label for insertion (e.g. "map/2" -> "map")
        const name = item.label.replace(/\/\d+$/, "")
        return {
          label: item.label,
          type: item.type === "module" ? "class" : "function",
          detail: item.detail,
          apply: name,
        }
      }),
    }
  }
}
