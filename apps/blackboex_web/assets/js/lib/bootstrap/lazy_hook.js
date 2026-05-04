function bindLiveViewApi(source, target) {
  target.el = source.el;
  target.pushEvent = source.pushEvent.bind(source);
  target.pushEventTo = source.pushEventTo.bind(source);
  target.handleEvent = source.handleEvent.bind(source);
}

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
