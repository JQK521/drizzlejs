# DrizzleJS v0.2.0
# -------------------------------------
# Copyright (c) 2014 Jaco Koo <jaco.koo@guyong.in>
# Distributed under MIT license

((root, factory) ->

    if typeof define is 'function' and define.amd
        define ['jquery', 'handlebars'], ($, Handlebars) -> factory root, $
    else if module and module.exports
        $ = require 'jquery'
        Handlebars = require 'handlebars'
        module.exports = factory root, $
    else
        root.Drizzle = factory root, $
) this, (root, $) ->

    D = Drizzle = version: '0.2.0'

    old = root.Drizzle
    idCounter = 0

    for item in ['Function', 'Object', 'Array', 'Number', 'Boolean', 'Date', 'RegExp', 'Undefined', 'Null']
        do (item) -> D["is#{item}"] = (obj) -> Object.prototype.toString.call(obj) is "[object #{item}]"

    D.extend = (target, mixins...) ->
        return target unless D.isObject target
        target[key] = value for key, value of mixin for mixin in mixins
        target

    D.extend D,
        uniqueId: (prefix) -> (if prefix then prefix else '') + ++i
        noConflict: ->
            root.Drizzle = old
            D
        joinPath: (paths...) -> paths.join('/').replace(/\/{2, }/g, '/')

    Drizzle.Base = class Base

        @include: (mixins...) ->
            @::[key] = value for key, value of mixin for mixin in mixins
            @

        @include Drizzle.Deferred

        constructor: (idPrefix) ->
            @id = Drizzle.uniqueId(idPrefix)
            @initialize()

        initialize: ->

        getOptionResult: (value) -> if _.isFunction value then value.apply @ else value

        extend: (mixins) ->
            return unless mixins

            doExtend = (key, value) =>
                if Drizzle.isFunction value
                    old = @[key]
                    @[key] = (args...) ->
                        args.unshift old if old
                        value.apply @, args
                else
                    @[key] = value unless @[key]

            doExtend key, value for key, value of mixins


    D.Application = class Application extends D.Base
        constructor: (@options = {}) ->
            @name = 'application'
            @modules = new Module.Container('Default Module Container')
            @global = {}
            @loaders = {}
            @regions = []

            super 'a'

        initialize: ->
            @registerLoader new D.Loader(@), true
            @registerHelper key, value for key, value of D.Helpers
            @setRegion new Region(@, null, $(document.body))

        registerLoader: (loader, isDefault) ->
            @loaders[loader.name] = loader
            @defaultLoader = loader if isDefault

        registerHelper: (name, fn) ->
            app = @
            Handlebars.registerHelper name, (args...) ->
                fn.apply @, [app, Handlebars].concat args

        getLoader: (name) ->
            {loader} = Loader.analyse name
            if loader and @loaders[loader] then @loaders[loader] else @defaultLoader

        setRegion: (region) ->
            @region = region
            @regions.unshift @region

        startRoute: (defaultPath, paths...) ->
            @router = new D.Router(@) unless @router

            @chain @router.mountRoutes paths..., ->
                @navigate defaultPath, true if defaultPath

        navigate: (path, trigger) ->
            @router.navigate(path, trigger)

        load: (names...) ->
            @chain (@getLoader(name).loadModule name for name in names)

        show: (feature, options) ->
            @region.show feature, options

        #methods for notification
        message:
            success: (title, content) ->
                alert content or title

            info: (title, content) ->
                content = title unless content
                alert content or title

            error: (title, content) ->
                content = title unless content
                alert content or title


    class ModuleContainer extends D.Base
        constructor: (@name) ->
            @modules = {}
            super

        checkId: (id) ->
            throw new Error "id: #{id} is invalid" unless id and _.isString id
            throw new Error "id: #{id} is already used" if @modules[id]

        get: (id) ->
            @modules[id]

        changeId: (from, to) ->
            return if from is to
            @checkId to

            module = @modules[from]
            throw new Error "module id: #{from} not exists" if not module
            delete @modules[from]
            module.id = to
            @modules[to] = module

        add: (module) ->
            @checkId module.id
            @modules[module.id] = module

        remove: (id) ->
            delete @modules[id]

    class Layout extends D.View
        initialize: ->
            @isLayout = true
            @loadDeferred = @chain [@loadTemplate(), @loadHandlers()]
            delete @bindData

    D.Module = class Module extends D.Base
        @Container = ModuleContainer
        @Layout = Layout
        constructor: (@name, @app, @loader, @options) ->
            [..., @baseName] = @name.split '/'
            @container = options.container or @app.modules
            @container.add @
            @separatedTemplate = options.separatedTemplate is true
            @regions = {}
            super 'm'

        initialize: ->
            @extend @options.extend if @options.extend
            @loadDeferred = @chain [@loadTemplate(), @loadLayout(), @loadData(), @loadItems()]

        loadTemplate: ->
            return if @separatedTemplate
            @chain @loader.loadTemplate(@), (template) -> @template = template

        loadLayout: ->
            layout = @getOptionResult @options.layout
            name = if _.isString layout then layout else layout?.name
            name or= 'layout'
            @chain @app.getLoader(name).loadLayout(@, name, layout), (obj) =>
                @layout = obj

        loadData: ->
            @data = {}
            promises = []
            items = @getOptionResult(@options.data) or {}
            @autoLoadDuringRender = []
            @autoLoadAfterRender = []

            doLoad = (id, value) =>
                name = D.Loader.analyse(id).name
                value = @getOptionResult value
                if value
                    if value.autoLoad is 'after' or value.autoLoad is 'afterRender'
                        @autoLoadAfterRender.push name
                    else if value.autoLoad
                        @autoLoadDuringRender.push name
                promises.push @chain @app.getLoader(id).loadModel(value, @), (d) -> @data[name] = d

            doLoad id, value for id, value of items

            @chain promises

        loadItems: ->
            @items = {}
            @inRegionItems = []

            promises = []
            items = @getOptionResult(@options.items) or []
            doLoad = (name, item) =>
                item = @getOptionResult item
                item = region: item if item and _.isString item
                isModule = item.isModule

                p = @chain @app.getLoader(name)[if isModule then 'loadModule' else 'loadView'](name, @, item), (obj) =>
                    @items[obj.name] = obj
                    obj.regionInfo = item
                    @inRegionItems.push obj if item.region
                promises.push p

            doLoad name, item for name, item of items

            @chain promises

        addRegion: (name, el) ->
            type = el.data 'region-type'
            @regions[name] = Region.create type, @app, @module, el

        removeRegion: (name) ->
            delete @regions[name]

        render: (options = {}) ->
            throw new Error 'No region to render in' unless @region
            @renderOptions = options
            @container.changeId @id, options.id if options.id

            @chain(
                @loadDeferred
                -> @options.beforeRender?.apply @
                -> @layout.setRegion @region
                @fetchDataDuringRender
                -> @layout.render()
                -> @options.afterLayoutRender?.apply @
                -> for value in @inRegionItems
                    key = value.regionInfo.region
                    region = @regions[key]
                    throw new Error "Can not find region: #{key}" unless region
                    region.show value
                -> @options.afterRender?.apply @
                @fetchDataAfterRender
                -> @
            )

        setRegion: (@region) ->

        close: -> @chain(
            -> @options.beforeClose?.apply @
            -> @layout.close()
            -> value.close() for key, value of @regions
            -> @options.afterClose?.apply @
            -> @container.remove @id
        )

        fetchDataDuringRender: ->
            @chain (@data[id].get?() for id in @autoLoadDuringRender)

        fetchDataAfterRender: ->
            @chain (@data[id].get?() for id in @autoLoadAfterRender)


    D.Model = class Data extends D.Base

        constructor: (@app, @module, @options = {}) ->
            @data = @options.data or {}
            @params = {}

            if options.pageable
                defaults = D.Config.pagination
                p = @pagination =
                    page: options.page or 1
                    pageCount: 0
                    pageSize: options.pageSize or defaults.pageSize
                    pageKey: options.pageKey or defaults.pageKey
                    pageSizeKey: options.pageSizeKey or defaults.pageSizeKey
                    recordCountKey: options.recordCountKey or defaults.recordCountKey

            super 'd'

        setData: (data) ->
            @data = if D.isFunction @options.parse then @options.parse data else data
            if p = @pagination
                p.recordCount = @data[p.recordCountKey]
                p.pageCount = Math.ceil(p.recordCount / p.pageSize)
            @data = @data[@options.root] if @options.root

        url: -> @getOptionResult(@options.url) or @getOptionResult(@url) or ''

        toJSON: -> @data

        getParams: ->
            d = {}
            if p = @pagination
                d[p.pageKey] = p.page
                d[p.pageSizeKey] = p.pageSize

            D.extend d, @params, @options.params

        clear: ->
            @data = {}
            if p = @pagination
                p.page = 1
                p.pageCount = 0

        turnToPage: (page, options) ->
            return @createRejectedDeferred() unless p = @pagination and page <= p.pageCount and page >= 1
            p.page = page
            @get options

        firstPage: (options) -> @turnToPage 1, options
        lastPage: (options) -> @turnToPage @pagination.pageCount, options
        nextPage: (options) -> @turnToPage @pagination.page + 1, options
        prevPage: (options) -> @turnToPage @pagination.page - 1, options

        getPageInfo: ->
            return {} unless p = @pagination
            d = if @data.length > 0
                start: (p.page - 1) * p.pageSize + 1, end: p.page * p.pageSize,  total: p.recordCount
            else
                start: 0, end: 0, total: 0

            d.end = d.total if d.end > d.total
            d

    for item in ['get', 'post', 'put', 'del']
        do (item) ->
        D.Model::[item] = (options) -> D.Require[item] @, options

    D.Model.include D.Event


    D.Region = class Region extends D.Base
        @types = {}
        @register: (name, clazz) -> @types[name] = clazz
        @create: (type, app, module, el) ->
            clazz = @types[type] or Region
            new clazz(app, module, el)

        constructor: (@app, @module, el) ->
            @el = if el instanceof $ then el else $ el
            super 'r'

            throw new Error "Can not find DOM element: #{el}" if @el.size() is 0

        getEl: -> @el

        # show the specified item which could be a view or a module
        show: (item, options) ->
            if @currentItem
                if (D.isObject(item) and item.id is @currentItem.id) or (D.isString(item) and D.loader.analyse(item).name is @currentItem.name)
                    return @chain @currentItem.render(options), @currentItem

            @chain (if D.isString(item) then @app.getLoader(item).loadModule(item) else item), (item) ->
                throw new Error "Can not show item: #{item}" unless item.render and item.setRegion
                item
            , [(item) ->
                item.region.close() if item.region
                item
            , ->
                @close()
            ], ([item]) ->
                item.setRegion @
                @currentItem = item
            , (item) ->
                item.render(options)

        close: ->
            return @createRejectedDeferred() unless @currentItem
            @chain ->
                @currentItem.close()
            , ->
                @empty()
                @currentItem = null
                @

        delegateEvent: (item, name, selector, fn) ->
            n = "#{name}.events#{@id}#{item.id}"
            if selector then @el.on n, selector, fn else @el.on n, fn

        undelegateEvents: (item) ->
            @el.off ".events#{@id}#{item.id}"

        $$: (selector) ->
            @el.find selector

        empty: -> @getEl().empty()


    D.View = class View extends Base
        @ComponentManager =
            handlers: {}
            register: (name, creator, destructor = ( -> ), initializer = ( -> )) ->
                @handlers[name] =
                    creator: creator, destructor: destructor, initializer: initializer, initialized: false

            create: (view, options = {}) ->
                {id, name, selector} = options
                opt = options.options
                throw new Error 'Component name can not be null' unless name
                throw new Error 'Component id can not be null' unless id

                dom = if selector then view.$$(selector) else if id then view.$(id) else view.getEl()
                handler = @handlers[name] or creator: (view, el, options) ->
                    throw new Error "No component handler for name: #{name}" unless el[name]
                    el[name] options
                , destructor: (view, component, info) ->
                    component[name] 'destroy'
                , initialized: true

                obj = if not handler.initialized and handler.initializer then handler.initializer() else null
                handler.initialized = true
                view.chain obj, handler.creator(view, dom, opt), (comp) ->
                    id: id, component: comp, info:
                        destructor: handler.destructor, options: opt

            destroy: (view, component, info) ->
                info.destructor?(view, component, info.options)

        constructor: (@name, @module, @loader, @options = {}) ->
            @id = D.uniqueId 'v'
            @app = @module.app
            @eventHandlers = {}
            super

        initialize: ->
            @extend @options.extend if @options.extend
            @loadDeferred = @chain [@loadTemplate(), @loadHandlers()]

        loadTemplate: ->
            if @module.separatedTemplate isnt true
                @chain @module.loadDeferred, -> @template = @module.template
            else
                template = @getOptionResult(@options.template) or @name
                @chain @app.getLoader(template).loadSeparatedTemplate(@, template), (t) ->
                    @template = t

        loadHandlers: ->
            handlers = @getOptionResult(@options.handlers) or @name
            @chain @app.getLoader(handlers).loadHandlers(@, handlers), (handlers) ->
                D.extend @eventHandlers, handlers

        # Bring model or collection from module to view, make them visible to render template
        # Bind model or collection events to call methods in view
        # eg.
        # bind: {
        #   item: 'all#render, reset#handlerName'
        # }
        bindData: -> @module.loadDeferred.done =>
            bind = @getOptionResult(@options.bind) or {}
            @data = {}
            doBind = (model, binding) => @listenTo model, event, (args...) ->
                [event, handler] = binding.split '#'
                throw new Error "Incorrect binding string format:#{binding}" unless name and handler
                return @[handler]? args...
                return @eventHandlers[handler]? args...
                throw new Error "Can not find handler function for :#{handler}"

            for key, value of bind
                @data[key] = @module.data[key]
                throw new Error "Model: #{key} doesn't exists" unless @data[key]
                return unless value
                bindings = value.replace(/\s+/g, '').split ','
                doBind @data[key], bindings for binding in bindings

        unbindData: ->
            @stopListening()
            delete @data

        wrapDomId: (id) -> "#{@id}#{id}"

        # Set the region to render in
        # Delegate all events in region
        setRegion: (@region) ->

            # Events can be defined like
            # events: {
            #   'eventName domElementId': 'handlerName'
            #   'click btn': 'clickIt'
            #   'change input-*': 'inputChanged'
            # }
            #
            # Only two type of selectors are supported
            # 1. Id selector
            #   'click btn' will effect with a dom element whose id is 'btn'
            #   eg. <button id="btn"/>
            #
            # 2. Id prefix selector
            #   'change input-*' will effect with those dom elements whose id start with 'input-'
            #   In this case, when event is performed,
            #   the string following with 'input-' will be extracted to the first of handler's argument list
            #   eg.
            #     <input id="input-1"/> <input id="input-2"/>
            #     When the value of 'input-1' is changed, the handler will get ('1', e) as argument list
            events = @getOptionResult(@options.events) or {}
            for key, value of events
                throw new Error 'The value defined in events must be a string' unless D.isString value
                [name, id] = key.replace(/^\s+/g, '').replace(/\s+$/, '').split /\s+/
                if id
                    selector = if id.charAt(id.length - 1) is '*' then "[id^=#{@wrapDomId id.slice(0, -1)}]" else "##{@wrapDomId id}"
                handler = @createHandler name, id, selector, value
                @region.delegateEvent @, name, selector, handler

        createHandler: (name, id, selector, value) ->
            me = @
            (args...) ->
                el = $ @

                return if el.hasClass 'disabled'

                if selector and selector.charAt(0) isnt '#'
                    i = el.attr 'id'
                    args.unshift i.slice id.length

                if el.data('after-click') is 'defer'
                    deferred = me.createDeferred()
                    el.addClass 'disabled'
                    deferred.always -> el.removeClass 'disabled'
                    args.unshift deferred

                me.loadDeferred.done ->
                    method = me.eventHandlers[value]
                    throw new Error "No handler defined with name: #{value}" unless method
                    method.apply me, args

        getEl: ->
            if @region then @region.getEl @ else null

        $: (id) ->
            throw new Error "Region is null" unless @region
            @region.$$ '#' + @wrapDomId id

        $$: (selector) ->
            throw new Error "Region is null" unless @region
            @getEl().find selector

        close: -> @chain(
            -> @options.beforeClose?.apply @
            [
                -> @region.undelegateEvents(@)
                -> @unbindData()
                -> @destroyComponents()
                -> @unexportRegions()
            ]
            -> @options.afterClose?.apply @
        )

        render: ->
            throw new Error 'No region to render in' unless @region

            @chain(
                @loadDeferred
                [@unbindData, @destroyComponents, @unexportRegions]
                @bindData
                -> @options.beforeRender?.apply(@)
                @beforeRender
                @serializeData
                @options.adjustData or (data) -> data
                @executeTemplate
                @processIdReplacement
                @renderComponent
                @exportRegions
                @afterRender
                -> @options.afterRender?.apply(@)
                -> @
            )

        beforeRender: ->

        destroyComponents: ->
            components = @components or {}
            for key, value of components
                View.ComponentManager.destroy @, value, @componentInfos[key]

            @components = {}
            @componentInfos = {}

        serializeData: ->
            data = {}
            data[key] = value.toJSON() for key, value of @data
            data

        executeTemplate: (data, ignore, deferred) ->
            data.Global = @app.global
            data.View = @
            html = @template data
            @getEl().html html

        processIdReplacement: ->
            used = {}

            @$$('[id]').each (i, el) =>
                el = $ el
                id = el.attr 'id'
                throw new Error "The id:#{id} is used more than once." if used[id]
                used[id] = true
                el.attr 'id', @wrapDomId id

            for attr in D.Config.attributesReferToId or []
                @$$("[#{attr}]").each (i, el) =>
                    el = $ el
                    value = el.attr attr
                    withHash = value.charAt(0) is '#'
                    if withHash
                        el.attr attr, '#' + @wrapDomId value.slice 1
                    else
                        el.attr attr, @wrapDomId value

        renderComponent: ->
            components = @getOptionResult(@options.components) or []
            promises = for component in components
                component = @getOptionResult component
                View.ComponentManager.create @, component if component
            @chain promises, (comps) =>
                for comp in comps when comp
                    id = comp.id
                    @components[id] = comp.component
                    @componentInfos[id] = comp.info

        exportRegions: ->
            @exportedRegions = {}
            @$$('[data-region]').each (i, el) =>
                el = $ el
                id = el.data 'region'
                @exportedRegions[id] = @module.addRegion id, el

        unexportRegions: ->
            @chain 'remove regions',
                (value.close() for key, value of @exportedRegions)
                (@module.removeRegion key for key, value of @exportedRegions)

        afterRender: ->

        listenTo: D.Event.listenTo

        stopListening: D.Event.stopListening


    D.Loader = class Loader extends D.Base
        @TemplateCache = {}

        @analyse: (name) ->
            return loader: null, name: name unless D.isString name

            [loaderName, name, args...] = name.split ':'
            if not name
                name = loaderName
                loaderName = null
            loader: loaderName, name: name, args: args

        constructor: (@app, @name = 'default') ->
            @fileNames = D.Config.fileNames
            super

        loadResource: (path, plugin) ->
            path = @app.path path
            path = plugin + '!' + path if plugin
            obj = @createDeferred()

            error = (e) ->
                if e.requireModules?[0] is path
                    define path, null
                    require.undef path
                    require [path], ->
                    obj.resolve null
                else
                    obj.reject null
                    throw e

            require [path], (obj) =>
                obj = obj(@app) if D.isFunction obj
                obj.resolve obj
            , error

            obj.promise()

        loadModuleResource: (module, path, plugin) ->
            @loadResource D.joinPath(module.name, path), plugin

        loadModule: (path, parentModule) ->
            {name} = Loader.analyse path
            @chain @loadResource(D.joinPath name, @fileNames.module), (options) =>
                new Module name, @app, @, options

        loadView: (name, module, options) ->
            {name} = Loader.analyse name
            @chain @loadModuleResource(module, @fileNames.view + name), (options) =>
                new View name, module, @, options

        loadLayout: (module, name, layout = {}) ->
            {name} = Loader.analyse name
            @chain @loadModuleResource(module, name), (options) =>
                new D.Module.Layout name, module, @, D.extend(layout, options)

        innerLoadTemplate: (module, p) ->
            path = p + @fileNames.templateSuffix
            template = Loader.TemplateCache[module.name + path]
            template = Loader.TemplateCache[module.name + path] = @loadModuleResource module, path, 'text' unless template

            @chain template, (t) ->
                if D.isString t
                    t = Loader.TemplateCache[path] = Handlebars.compile t
                t

        #load template for module
        loadTemplate: (module) ->
            path = @fileNames.templates
            @innerLoadTemplate module, path

        #load template for view
        loadSeparatedTemplate: (view, name) ->
            path = @fileNames.template + name
            @innerLoadTemplate view.module, path

        loadModel: (name = '', module) ->
            return name if name instanceof D.Model
            name = url: name if D.isString name
            new D.Model(@app, module, name)

        loadHandlers: (view, name) ->
            view.options.handlers or {}

        loadRouter: (path) ->
            {name} = Loader.analyse path
            path = D.joinPath name, @fileNames.router
            path = path.substring(1) if path.charAt(0) is '/'
            @loadResource(path)


    class Route
        regExps: [
            /:([\w\d]+)/g
            '([^\/]+)'
            /\*([\w\d]+)/g
            '(.*)'
        ]
        constructor: (@app, @router, @path, @fn) ->
            pattern = path.replace(@regExps[0], @regExps[1]).replace(@regExps[2], @regExps[3])
            @pattern = new RegExp "^#{pattern}$", if D.Config.caseSensitiveHash then 'g' else 'gi'

        match: (hash) -> @pattern.test hash

        handle: (hash) ->
            args = @pattern.exec(hash).slice 1
            routes = @router.getDependencies(@path)
            routes.push @
            fns = for route, i in routes
                (prev) -> route.fn (if i > 0 then [prev].concat args else args)...
            router.chain fns...

    D.Router = class Router extends D.Base
        constructor: (@app) ->
            @routes = []
            @routeMap = {}
            @dependencies = {}
            super 'ro'

        start: (defaultPath) ->
            $(root).on 'popstate.drizzlerouter', =>
                hash = root.location.hash.slice 1
                return if @previousHash is hash
                @previousHash = hash
                @dispatch(hash)
            @navigate defaultPath, true if defaultPath

        stop: -> $(root).off '.drizzlerouter'

        dispatch: (hash) -> return route.handle hash for route in @routes when route.match hash

        navigate: (path, trigger) ->
            root.history.pushState {}, root.document.title, "##{path}"
            @routeMap[path]?.handle path if trigger

        mountRoutes: (paths...) -> @chain(
            @app.getLoader(path).loadRouter(path) for path in paths
            (routers) ->
                @addRouter paths[i], router for router, i in routers
        )

        addRoute: (path, router) ->
            routes = @getOptionResult router.route
            dependencies = @getOptionResult router.deps
            for key, value of dependencies
                p = D.joinPath path, key
                @dependencies[p] = if value.charAt(0) is '/' then value.slice 1 else D.joinPath path, value

            for key, value of routes
                p = D.joinPath path, key
                route = new Route @app, @, p, router[value]
                @routes.unshift route
                @routeMap[p] = route

        getDependencies: (path) ->
            deps = []
            d = @dependencies[path]
            while d?
                deps.unshift @routeMap[d]
                d = @dependencies[d]
            deps


    Drizzle.Config =
        scriptRoot: 'app'
        urlRoot: ''
        urlSuffix: ''
        caseSensitiveHash: false
        attributesReferToId: [
            'for' # for label
            'data-target' #for bootstrap
            'data-parent' #for bootstrap
        ]

        fileNames:
            module: 'index'           # module definition file name
            templates: 'templates'    # merged template file name
            view: 'view-'             # view definition file name prefix
            template: 'template-'     # seprated template file name prefix
            handler: 'handler-'       # event handler file name prefix
            model: 'model-'           # model definition file name prefix
            collection: 'collection-' # collection definition file name prefix
            router: 'router'
            templateSuffix: '.html'

        pagination:
            defaultPageSize: 10
            pageKey: '_page'
            pageSizeKey: '_pageSize'
            recordCountKey: 'recordCount'


    D.Deferred =

        createDeferred: -> $.Deferred()

        createRejectedDeferred: (args...) ->
            d = @createDeferred()
            d.reject args...
            d

        deferred: (fn, args...) ->
            fn = fn.apply @, args if D.isFunction fn
            return fn.promise() if fn?.promise
            obj = @createDeferred()
            obj.resolve fn
            obj.promise()

        chain: (rings...) ->
            obj = @createDeferred()
            if rings.length is 0
                obj.resolve()
                return obj.promise()

            gots = []
            doItem = (item, i) =>
                gotResult = (data) ->
                    data = data[0] if not D.isArray(item) and data.length < 2
                    gots.push data

                (if D.isArray item
                    promises = for inArray in item
                        args = [inArray]
                        args.push gots[i - 1] if i > 0
                        @deferred(args...)
                    $.when(promises...)
                else
                    args = [item]
                    args.push gots[i - 1] if i > 0
                    @deferred(args...)
                ).done (data...) ->
                    gotResult data
                    if rings.length is 0 then obj.resolve gots... else doItem(rings.shift(), ++i)
                .fail (data...) ->
                    gotResult data
                    obj.reject gots...

            doItem rings.shift(), 0
            obj.promise()


    D.Event =
        on: (name, callback, context) ->
            @registeredEvents or= {}
            (@registeredEvents[name] or= []).push fn: callback, context: context
            @

        off: (name, callback, context) ->
            return @ unless @registeredEvents and events = @registeredEvents[name]
            @registeredEvents[name] = (item for item in events when item.fn isnt callback or (context and context isnt item.context))
            @

        trigger: (name, args...) ->
            return @ unless @registeredEvents and events = @registeredEvents[name]
            item.fn.apply item.context, args for item in events
            @

        listenTo: (obj, name, callback) ->
            @registeredListeners or= {}
            (@registeredListeners[name] or= []).push fn: callback, obj: obj
            obj.on name, callback, @
            @

        stopListening: (obj, name, callback) ->
            return @ unless @registeredListeners
            unless obj
                value.obj.off key, value.fn, @ for key, value of @registeredListeners
                return @

            for key, value of @registeredListeners
                continue if name and name isnt key
                @registeredListeners[key] = []
                for item in value
                    if item.obj isnt obj or (callback and callback isnt item.fn)
                        @registeredListeners[key].push item
                    else
                        item.obj.off key, item.fn, @
            @


    D.Request =

        url: (model) ->
            urls = [D.Config.urlRoot]
            url.push model.module.options.urlPrefix if model.module.options.urlPrefix
            url.push model.module.name
            base = model.url or ''
            base = base.apply model if D.isFunction base

            while base.indexOf('../') is 0
                paths.pop()
                base = base.slice 3

            urls.push base
            urls.push model.data.id if model.data.id
            D.joinPath urls...

        get: (model, options) -> @ajax type: 'GET', model, model.getParams(), options
        post: (model, options) -> @ajax type: 'POST', model, model.data, options
        put: (model, options) -> @ajax type: 'PUT', model, model.data, options
        del: (model, options) -> @ajax type: 'DELETE', model, model.data, options

        ajax: (params, model, data, options) ->
            url = @url model
            params = D.extend params,
                contentType: 'application/json'
            , options
            data = D.extend data, options.data
            params.url = url
            params.data = data
            D.Deferred.chain $.ajax(params), (resp) -> model.setData resp


    D.Helpers =
        layout: (app, Handlebars, options) ->
            if @View.isLayout then options.fn @ else ''

        view: (app, Handlebars, name, options) ->
            return '' if @View.isLayout or @View.name isnt name
            options.fn @


    Drizzle
