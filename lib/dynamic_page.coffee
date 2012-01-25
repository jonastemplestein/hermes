_ = require "underscore"
async = require "async"
jsdom = require "jsdom"
request = require "request"

URL = require "url"
fs = require "fs"
path = require "path"

###
  `DynamicPage` takes a URL, downloads it, runs the javascript and returns the HTML.
  
  Other than the constructor, the function you want to be calling is page.scrape()

  DynamicPage exposes a few variables to the running page:
    
    - window.isHermes is set to true. use this to prevent lengthy or broken things
      from running

    - window.Hermes.log pipes log messages to DynamicPage (depending on
      @options.showBrowserLog)

    - window.Hermes.finish can be called when the page is positive that it's now
      finished. if not set, the timeout is used

    - window.Hermes.error404 can be called to let Hermes know not to return any
      content

###
class DynamicPage

  # a simple cache to prevent pulling the same file over and over
  # TODO seems like the wrong place for a cache
  @_resourceCache:
    "jquery.js": fs.readFileSync __dirname + "/../assets/jquery.js", "utf8"

  # Fetches a resource that is either relative to the current page or absolute
  # URL
  getResource: (url, cb) ->
    return cb null, DynamicPage._resourceCache[url] if DynamicPage._resourceCache[url]
    try
      url = @makeAbsoluteUrl url

      request url, (err, response, body) =>
        return cb err if err
        DynamicPage._resourceCache[url] = body
        return cb null, body
    catch e then cb e


  # TODO take <base href="..."> into consideration
  # TODO use base directory from url if no base href is given
  # ghetto builder of absolute urls
  makeAbsoluteUrl: (url) ->
    # make sure that local resources are loaded correctly
    parsed = URL.parse url
    return url if parsed.host
    _.defaults parsed, @url
    return URL.format parsed

  defaultOptions:

    # Give up after `timeout` milliseconds and return whatever html is there at
    # the time
    scrapeTimeout: 5000

    # turn these things on if you run into trouble (aka turn these things on).
    showBrowserLog: false
    showScrapingLog: true
    
    # Logging function
    log: ->  console.log "#{new Date().toISOString()} - ", arguments...
   

  constructor: (url, @options={}) ->
    throw new Error "`url` parameter is required" if not url
    @url = URL.parse url
    @hash = @url.hash or ""
    delete @url.hash
    delete @url.href

    _.defaults @options, @defaultOptions
    
  # Runs a given bit of javascript in the context of @window. This will temporarily
  # change the implementation features of the DOM to process external resources.
  # This could lead to unexpected behavior in some cases where you're trying to
  # do other things in parallel.
  loadInlineScript: (scriptSource, cb) ->
    if not @window
      throw new Error "missing @window, call @initJsdom() first"

    try
      scriptTag = @window.document.createElement "script"
      scriptTag.text = scriptSource
      done = (err) => _.defer cb 
      scriptTag.onload = -> done null
      scriptTag.onError = done
      @window.document.documentElement.appendChild scriptTag
      @window.document.documentElement.removeChild scriptTag
    catch e then cb e

  # External scripts are run like inline scripts which allows us to take
  # advantage of caching
  loadExternalScript: (url, cb) ->
    @getResource url, (err, scriptSource) =>
      return cb err if err
      @loadInlineScript scriptSource, cb

  # injects the local jquery into the page and loads it into noConflict
  loadJQuery: (cb) ->
    @getResource "jquery.js", (err, scriptSource) =>
      return cb err if err
      scriptSource += "\n window._externalJQuery = window.$.noConflict(true);"
      @loadInlineScript scriptSource, (err) =>
        return cb err if err
        @$ = @window._externalJQuery
        return cb null, @$

  # this is where the magic happens
  initJsdom: (html) ->
    options = 
      url: URL.format @url
      # Don't initially fetch resources or process inline JS
      features:
        FetchExternalResources   : false
        ProcessExternalResources : false

    @jsdomDoc = jsdom.jsdom html, null, options
    @window = @jsdomDoc.createWindow()

    # After the initial load, we're ready to process the shit out of everything
    # TODO make sure this never causes the initial javascript on the page to execute
    @window.document.implementation.addFeature('FetchExternalResources', ['script']);
    @window.document.implementation.addFeature('ProcessExternalResources', ['script']);

    return @window

  # Processing the first few scripts is a bit tricky. We prevent automatic
  # execution by jsdom because we want more control. we then walk through the
  # scripts one by one and download and execute them
  processInitialScripts: (cb) ->
    if not @window and @$
      return cb new Error "@window and @$ missing" 

    externalScripts = []
    inlineScripts = []

    @$("script").each (i, scriptTag) =>
      $script = @$(scriptTag)
      src = $script.attr("src")
      # TODO Ummm ... are there scripts with both a src and inline content ..?
      if src then externalScripts.push src
      else inlineScripts.push $script.html()
    
    # Load external scripts first
    async.series
      
      "Load external scripts": (doneExternal) =>
        async.forEachSeries externalScripts, (srcAttr, doneScript) =>
          @loadExternalScript srcAttr, doneScript
        , doneExternal

      "Load inline scripts": (doneInline) =>
        async.forEachSeries inlineScripts, (scriptSource, doneScript) =>
          @loadInlineScript scriptSource, doneScript
        , doneInline

    , (err) =>
      @log "Processed all scripts"
      return cb err
    
  # attach a node XMLHttpRequest implementation to the DOM
  loadXMLHttpRequest: ->
    if not @window
      throw new Error "@window missing"
    @window.XMLHttpRequest = require("xmlhttprequest").XMLHttpRequest

  # returns data property that is passed as third arg to scrape callback.
  # Currently only provides fragments (array of other hash fragments found on
  # page) and title (title of page)
  scrapeData: ->
    fragmentsDedup = {}
    # Find interesting internal links. Checks to see if protocol, slashes,
    # host, hostname, pathname and path properties of parsed url match with
    # base url or if the host is missing (relative links a la "#!someplace")
    # TODO this probably breaks in some cases and is not really thorough
    @$("a").each (i, a) =>
      $a = @$(a)
      href = $a.attr "href"
      return if not href
      hrefParsed = URL.parse href
      hash = hrefParsed.hash
      delete hrefParsed.hash
      delete hrefParsed.href
      if not hrefParsed.host or _.isEqual hrefParsed, @url
        fragmentsDedup[hash] = 1
    data =
      fragments: _.keys fragmentsDedup
      title: @window.document.title
    return data
    

  # TODO doesn't return the doctype if there is one
  getFullHtml: (window) ->
    inner = window.document.documentElement.innerHTML
    # get attributes on html tag
    htmlAttrs = ""
    for attr in @$("html")[0].attributes
      htmlAttrs += " #{attr.name}=\"#{attr.value}\""
    return "<html#{htmlAttrs}>\n#{inner}\n</html>"

  # Scrapes the page and calls the callback `cb(err, htmlContent, data)`
  # `data` is an object that contains scraping data, including follow-up links
  scrape: (cb) ->

    if @_scrapeTimeout
      throw new Error "scrape() called while another scrape was underway"

    # `finishScrape` is called when the scrape timeout is over,
    # window.Hermes.finish() was called from within the scraped page or an error
    # occurred 

    finishScrape = (err) =>
      clearTimeout @_scrapeTimeout if @_scrapeTimeout
      delete @_scrapeTimeout
      return cb err if err
      cb null, @getFullHtml(@window), @scrapeData()

    error404 = =>
      clearTimeout @_scrapeTimeout if @_scrapeTimeout
      delete @_scrapeTimeout
      return cb null, null

    ifNotDone = (cb) =>
      return ->
        if not @_scrapeTimeout then cb arguments...
        else
          @log "Attempted to do stuff after scrape was finished"
          return

    @_scrapeTimeout = setTimeout ifNotDone(finishScrape), @options.scrapeTimeout

    @getResource URL.format(@url), (err, html) =>
      return cb err if err

      async.series

        "init jsdom": (done) =>
          @initJsdom html
          ifNotDone(done)()
        
        "init hermes": (done) =>
          @window.isHermes = true
          @window.Hermes =
            error404: => 
              @log "page says it's 404"
              ifNotDone(error404)()
            finish: =>
              @log "page says it's finished"
              ifNotDone(finishScrape)()

          if @options.showBrowserLog
            @window.Hermes.log = =>
              @options.log "[client]", arguments...

          ifNotDone(done)()

        "load XHR plugin": (done) =>
          @loadXMLHttpRequest()
          ifNotDone(done)()

        "load our own jquery": (done) =>
          @loadJQuery ifNotDone(done)

        "go to hash": (done) =>
          @loadInlineScript "window.location.hash = \"#{@hash}\"", ifNotDone(done)

        "load all other scripts": (done) =>
          @processInitialScripts ifNotDone(done)

      , (err) =>
        return finishScrape err if err
     
  log: ->
    if @options.showScrapingLog
      @options.log arguments...

  # Frees all possible memory leaks
  # ... NOT ... maybe ... ?
  free: ->
    @window.close()
    delete @window
    delete @jsdomDocument

module.exports = DynamicPage

