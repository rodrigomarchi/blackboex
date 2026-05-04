/**
 * @file Vitest helpers for mounting and exercising LiveView hooks.
 */
/**
 * @typedef {object} PushedEvent
 * @property {string | undefined} target - Optional pushEventTo target element.
 * @property {string} event - LiveView event name.
 * @property {object | undefined} payload - Payload passed by the hook.
 */
if (!Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = function () {};
}

/**
 * Mounts a LiveView hook object against jsdom and records pushed events.
 *
 * The helper creates a hook instance with `el`, `pushEvent`, `pushEventTo`,
 * and `handleEvent` stubs, then calls `mounted()` so hook tests can exercise
 * lifecycle behavior without Phoenix LiveView.
 * @param {object} hookDef - LiveView hook definition object.
 * @param {Element | {tag?: string, html?: string, attrs?: Record<string, string>, parent?: HTMLElement}} options - Existing element or element creation options.
 * @returns {object} Mounted hook instance with test-only event recording fields.
 */
export function mountHook(hookDef, options = {}) {
  let el;
  if (options instanceof Element) {
    el = options;
    if (!el.parentElement) document.body.appendChild(el);
  } else {
    const { tag = "div", html = "", attrs = {}, parent } = options;
    el = document.createElement(tag);
    el.innerHTML = html;
    for (const [key, value] of Object.entries(attrs)) {
      el.setAttribute(key, value);
    }

    const parentEl = parent || document.body;
    parentEl.appendChild(el);
  }

  const hook = Object.create(hookDef);
  hook.el = el;
  hook.__pushEvents = [];
  hook.__eventHandlers = {};

  hook.pushEvent = vi.fn((event, payload, callback) => {
    hook.__pushEvents.push({ event, payload });
    if (callback) callback({});
  });

  hook.pushEventTo = vi.fn((target, event, payload) => {
    hook.__pushEvents.push({ target, event, payload });
  });

  hook.handleEvent = vi.fn((event, callback) => {
    if (!hook.__eventHandlers[event]) hook.__eventHandlers[event] = [];
    hook.__eventHandlers[event].push(callback);
  });

  if (hook.mounted) hook.mounted();

  return hook;
}

/**
 * Invokes handlers registered through the hook's `handleEvent` stub.
 * @param {{__eventHandlers: Record<string, Array<Function>>}} hook - Mounted hook from `mountHook`.
 * @param {string} event - LiveView event name to simulate.
 * @param {object} payload - Server payload to pass to registered handlers.
 * @returns {void}
 */
export function simulateEvent(hook, event, payload) {
  const handlers = hook.__eventHandlers[event] || [];
  handlers.forEach((handler) => handler(payload));
}

/**
 * Returns payloads pushed for a specific LiveView event name.
 * @param {{__pushEvents: Array<PushedEvent>}} hook - Mounted hook from `mountHook`.
 * @param {string} eventName - LiveView event name to filter.
 * @returns {Array<object | undefined>} Payloads pushed for the requested event.
 */
export function getPushEvents(hook, eventName) {
  return hook.__pushEvents
    .filter((event) => event.event === eventName)
    .map((event) => event.payload);
}

/**
 * Clears jsdom state and restores Vitest mocks between hook tests.
 * @returns {void}
 */
export function cleanupDOM() {
  document.body.innerHTML = "";
  document.documentElement.removeAttribute("style");
  vi.restoreAllMocks();
}

/**
 * Installs an in-memory localStorage mock with a `restore()` helper.
 * @returns {Storage & {store: Record<string, string>, restore: Function}} Mock storage object.
 */
export function mockLocalStorage() {
  const store = {};
  const original = globalThis.localStorage;

  const mock = {
    getItem: vi.fn((key) => store[key] ?? null),
    setItem: vi.fn((key, value) => {
      store[key] = String(value);
    }),
    removeItem: vi.fn((key) => {
      delete store[key];
    }),
    clear: vi.fn(() => {
      Object.keys(store).forEach((key) => delete store[key]);
    }),
    key: vi.fn((index) => Object.keys(store)[index] ?? null),
    get length() {
      return Object.keys(store).length;
    },
  };

  Object.defineProperty(globalThis, "localStorage", {
    value: mock,
    writable: true,
    configurable: true,
  });

  mock.store = store;
  mock.restore = () => {
    Object.defineProperty(globalThis, "localStorage", {
      value: original,
      writable: true,
      configurable: true,
    });
  };

  return mock;
}
