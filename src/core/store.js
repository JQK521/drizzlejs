D.Store = class Store extends D.Base {
    constructor (mod, options) {
        super('Store', options, {
            app: mod.app,
            module: mod,
            _models: {}
        });

        this.app.delegateEvent(this);

        this._callbacks = this._option('callbacks');
        mapObj(this._callbacks, (value, key) => {
            if (key.slice(0, 4) === 'app.') {
                this.listenTo(this.app, key, (payload) => value.call(this._callbackContext, payload));
                return;
            }

            if (key.slice(0, 7) === 'shared.') {
                const name = key.slice(7), model = this._models[name];
                if (!model || model.store === this) this._error(`Can not bind to model: ${key}`);
                this.listenTo(model, 'changed', () => value.call(this._callbackContext));
            }
        });
    }

    get models () {return this._models;}

    dispatch (name, payload) {
        let callback, n = name, p = payload;
        if (D.isObject(n)) {
            p = n.payload;
            n = n.name;
        }

        callback = this._callbacks[n];
        if (!callback) this._error(`No action callback for name: ${name}`);
        return this.chain(callback.call(this._callbackContext, p));
    }

    _initialize () {
        this._initializeModels();
        this._callbackContext = assign({
            app: this.app,
            models: this.models,
            module: this.module,
            chain: this.chain
        }, D.Request);

        this._callbackContext.Promise = new D.Promise(this._callbackContext);
    }

    _initializeModels () {
        mapObj(this._option('models'), (value, key) => {
            const v = (D.isFunction(value) ? value.call(this) : value) || {};
            if (v.shared === true) {
                if (this.app.viewport) {
                    this._models[key] = this.app.viewport.store.models[key];
                    return;
                }
                if (this.module.name === this.app._option('viewport')) {
                    this._error('Can not define shared model in viewport');
                }
                if (this.module.module && this.module.module.name === this.app._option('viewport')) {
                    this._models[key] = this.module.module.store.models[key];
                }
                return;
            }
            this._models[key] = this.app._createModel(this, v);
        });
    }

    _loadEagerModels () {
        return this.chain(mapObj(this._models, (model) => {
            if (model.store !== this) return null;
            return model.options.autoLoad === true ? D.Request.get(model) : null;
        }));
    }

    _loadLazyModels () {
        return this.chain(mapObj(this._models, (model) => {
            if (model.store !== this) return null;
            const { autoLoad } = model.options;
            return autoLoad && autoLoad !== true ? D.Request.get(model) : null;
        }));
    }

    _destory () {
        this.stopListening();
    }
};
