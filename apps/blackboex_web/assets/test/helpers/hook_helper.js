/**
 * @file Vitest helpers for mounting and exercising LiveView hooks.
 */
/**
 * @typedef {object} PushedEvent
 * @property {string | undefined} target
 * @property {string} event
 * @property {object | undefined} payload
 */
if (!Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = function () {};
}

/**
 * Provides mount hook.
 * @param {unknown} hookDef - hookDef value.
 * @param {unknown} options - Configuration values for the helper.
 * @returns {unknown} Function result.
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
 * Provides simulate event.
 * @param {unknown} hook - LiveView hook instance or test double.
 * @param {unknown} event - Browser or library event payload.
 * @param {unknown} payload - Payload passed to the helper.
 * @returns {unknown} Function result.
 */
export function simulateEvent(hook, event, payload) {
  const handlers = hook.__eventHandlers[event] || [];
  handlers.forEach((handler) => handler(payload));
}

/**
 * Provides get push events.
 * @param {unknown} hook - LiveView hook instance or test double.
 * @param {unknown} eventName - eventName value.
 * @returns {unknown} Function result.
 */
export function getPushEvents(hook, eventName) {
  return hook.__pushEvents
    .filter((event) => event.event === eventName)
    .map((event) => event.payload);
}

/**
 * Provides cleanup dom.
 * @returns {unknown} Function result.
 */
export function cleanupDOM() {
  document.body.innerHTML = "";
  document.documentElement.removeAttribute("style");
  vi.restoreAllMocks();
}

/**
 * Provides mock local storage.
 * @returns {unknown} Function result.
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
