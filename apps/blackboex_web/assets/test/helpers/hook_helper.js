if (!Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = function () {};
}

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

export function simulateEvent(hook, event, payload) {
  const handlers = hook.__eventHandlers[event] || [];
  handlers.forEach((handler) => handler(payload));
}

export function getPushEvents(hook, eventName) {
  return hook.__pushEvents
    .filter((event) => event.event === eventName)
    .map((event) => event.payload);
}

export function cleanupDOM() {
  document.body.innerHTML = "";
  document.documentElement.removeAttribute("style");
  vi.restoreAllMocks();
}

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
