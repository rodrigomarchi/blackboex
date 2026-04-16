/**
 * ResizablePanels hook — manages drag-to-resize for playground panels.
 *
 * Looks for elements with [data-resize-handle] inside the hook element.
 * Each handle needs:
 *   - data-resize-direction="vertical" | "horizontal"
 *   - data-resize-target="<id of the panel to resize>"
 *
 * Vertical handles control height, horizontal handles control width.
 * Sizes are persisted to localStorage and restored on mount.
 */
const STORAGE_KEY = "playground-panel-sizes"

const CONSTRAINTS = {
  vertical: { min: 100, max: 600 },
  horizontal: { min: 200, max: 500 },
}

export default {
  mounted() {
    this.handles = []
    this.restoreSizes()
    this.setupHandles()
  },

  destroyed() {
    this.cleanup()
  },

  setupHandles() {
    const handles = this.el.querySelectorAll("[data-resize-handle]")

    handles.forEach((handle) => {
      const direction = handle.dataset.resizeDirection
      const targetId = handle.dataset.resizeTarget
      const target = document.getElementById(targetId)

      if (!target) return

      const state = {
        handle,
        direction,
        target,
        dragging: false,
        startPos: 0,
        startSize: 0,
      }

      const onMouseDown = (e) => this.startDrag(e, state)
      const onTouchStart = (e) => this.startDrag(e.touches[0], state)

      handle.addEventListener("mousedown", onMouseDown)
      handle.addEventListener("touchstart", onTouchStart, { passive: true })

      this.handles.push({
        state,
        cleanup: () => {
          handle.removeEventListener("mousedown", onMouseDown)
          handle.removeEventListener("touchstart", onTouchStart)
        },
      })
    })
  },

  startDrag(e, state) {
    e.preventDefault()
    state.dragging = true

    if (state.direction === "vertical") {
      state.startPos = e.clientY || e.pageY
      state.startSize = state.target.offsetHeight
    } else {
      state.startPos = e.clientX || e.pageX
      state.startSize = state.target.offsetWidth
    }

    // Add overlay to prevent iframe/editor from capturing events
    this.overlay = document.createElement("div")
    this.overlay.style.cssText =
      "position:fixed;inset:0;z-index:9999;cursor:" +
      (state.direction === "vertical" ? "row-resize" : "col-resize")
    document.body.appendChild(this.overlay)

    const onMouseMove = (e) => this.onDrag(e, state)
    const onTouchMove = (e) => this.onDrag(e.touches[0], state)
    const onEnd = () => this.endDrag(state, onMouseMove, onTouchMove, onEnd)

    document.addEventListener("mousemove", onMouseMove)
    document.addEventListener("touchmove", onTouchMove, { passive: true })
    document.addEventListener("mouseup", onEnd)
    document.addEventListener("touchend", onEnd)
  },

  onDrag(e, state) {
    if (!state.dragging) return

    const constraints = CONSTRAINTS[state.direction]
    let newSize

    if (state.direction === "vertical") {
      const delta = state.startPos - (e.clientY || e.pageY)
      newSize = Math.min(
        Math.max(state.startSize + delta, constraints.min),
        constraints.max
      )
      state.target.style.height = newSize + "px"
    } else {
      const delta = state.startPos - (e.clientX || e.pageX)
      newSize = Math.min(
        Math.max(state.startSize + delta, constraints.min),
        constraints.max
      )
      state.target.style.width = newSize + "px"
    }
  },

  endDrag(state, onMouseMove, onTouchMove, onEnd) {
    state.dragging = false

    if (this.overlay) {
      this.overlay.remove()
      this.overlay = null
    }

    document.removeEventListener("mousemove", onMouseMove)
    document.removeEventListener("touchmove", onTouchMove)
    document.removeEventListener("mouseup", onEnd)
    document.removeEventListener("touchend", onEnd)

    this.saveSizes()
  },

  saveSizes() {
    const sizes = {}
    this.handles.forEach(({ state }) => {
      const prop =
        state.direction === "vertical" ? "offsetHeight" : "offsetWidth"
      sizes[state.target.id] = state.target[prop]
    })

    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(sizes))
    } catch (_) {
      // localStorage may be unavailable
    }
  },

  restoreSizes() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (!stored) return

      const sizes = JSON.parse(stored)
      Object.entries(sizes).forEach(([id, size]) => {
        const el = document.getElementById(id)
        if (!el) return

        const handle = this.el.querySelector(
          `[data-resize-target="${id}"]`
        )
        if (!handle) return

        const direction = handle.dataset.resizeDirection
        const constraints = CONSTRAINTS[direction]
        const clamped = Math.min(Math.max(size, constraints.min), constraints.max)

        if (direction === "vertical") {
          el.style.height = clamped + "px"
        } else {
          el.style.width = clamped + "px"
        }
      })
    } catch (_) {
      // Ignore parse errors
    }
  },

  cleanup() {
    this.handles.forEach(({ cleanup }) => cleanup())
    this.handles = []

    if (this.overlay) {
      this.overlay.remove()
      this.overlay = null
    }
  },
}
