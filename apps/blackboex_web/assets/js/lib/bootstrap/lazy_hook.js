/**
 * @file Lazy LiveView hook loader that preserves Phoenix hook lifecycle APIs.
 */
/**
 * Copies Phoenix-provided hook APIs onto a lazily created hook instance.
 * @param {object} source - Mounted LiveView hook shell supplied by Phoenix.
 * @param {object} target - Hook object created from the loaded module.
 * @returns {void}
 */
function bindLiveViewApi(source, target) {
  target.el = source.el;
  target.pushEvent = source.pushEvent.bind(source);
  target.pushEventTo = source.pushEventTo.bind(source);
  target.handleEvent = source.handleEvent.bind(source);
}

/**
 * Creates a hook proxy that imports its real implementation on first mount.
 *
 * `updated()` calls that arrive before the import resolves are replayed once
 * the implementation is mounted. `destroyed()` prevents late mounts after the
 * LiveView node has been removed.
 *
 * @param {() => Promise<object>} loader - Dynamic import returning a hook object or default export.
 * @returns {object} LiveView hook proxy.
 */
export function lazyHook(loader) {
  return {
    mounted() {
      this.__lazyHook = {
        destroyed: false,
        instance: null,
        pendingUpdated: false,
      };

      this.__lazyHook.promise = loader().then((module) => {
        const hookDef = module.default || module;
        if (this.__lazyHook.destroyed) return null;

        const instance = Object.create(hookDef);
        bindLiveViewApi(this, instance);
        this.__lazyHook.instance = instance;

        if (instance.mounted) instance.mounted();
        if (this.__lazyHook.pendingUpdated && instance.updated) {
          instance.updated();
          this.__lazyHook.pendingUpdated = false;
        }

        return instance;
      });
    },

    updated() {
      const state = this.__lazyHook;
      if (!state) return;

      if (state.instance?.updated) {
        bindLiveViewApi(this, state.instance);
        state.instance.updated();
      } else {
        state.pendingUpdated = true;
      }
    },

    destroyed() {
      const state = this.__lazyHook;
      if (!state) return;

      state.destroyed = true;
      if (state.instance?.destroyed) state.instance.destroyed();
    },
  };
}
