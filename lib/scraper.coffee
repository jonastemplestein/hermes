DynamicPage = require "./dynamic_page"
_ = require "underscore"
async = require "async"
mkdirp = require "mkdirp"
URL = require "url"
fs = require "fs"
path = require "path"

###
  `Scraper` is built on top of `DynamicPage` and is used to scrape dynamic pages
  within the same site that are represented by hash fragments. `Scraper` also
  writes the compiled pages to disk.

  For okay results, hook up a `Scraper` to a `Server` as dynamic build function.
  This won't make your page fast for Google, but Facebook like buttons and the like
  will be able to scrape your site (their timeout seems to be 10 - 15 secs)

  For best results, hook up your application logic to a rabbitmq server or something
  and let a Scraper know when knew pages appear or it's time to update old one.

  EXPERIMENTAL: Also has some fancy crawling features that are fun to play around
  with.

  TODO set max-age on pages and re-crawl automatically
  TODO scale to multiple processes
  TODO don't crash all the time
###

_stripHashbang = /^#*!\/*/
class Scraper

  defaultOptions:

    # This will cause it to run forever
    memoryDebug: false
    memoryDebugInterval: 10000

    # set to true to follow links when crawling. call scraper.crawl()
    crawl: false
    
    # `includeFilters` and `excludeFilters` can be strings (exact match) or
    # regexps. `includeFilters` are necessary conditions that all fragments must
    # pass. A fragment must not match any `excludeFilters`. The exclusion filters
    # are just a convenience
    includeFilters: [/^#!/]
    excludeFilters: []

    # Directory relative to `pwd` that static files are written to
    outputDir: "./static"

    # Function to convert fragments "#!/asdasdasdasdasdasdad?a=b" to filenames.
    # The extension is added through @options.fileExtension
    fragmentToPath: (fragment) -> fragment.replace _stripHashbang, ""

    # used if fragmentToPath(fragment) evaluates to an empty string
    indexName: "index"
    
    # Extension of written files
    extension: ".html"

    # Set these to override the default DynamicPage behavior
    pageOptions:
      timeout: 5000 

    log: -> console.log new Date().toISOString(), arguments...

  # create a scraper. requires a baseUrl parameter
  constructor: (baseUrl, options={}) ->
    throw new Error "need a baseUrl for Scraper" if not baseUrl

    # Parse options ... clumsily
    pageOptions = options.pageOptions or {}
    delete options.pageOptions
    _.defaults options, @defaultOptions
    pageOptions.log ||= options.log
    _.extend options.pageOptions, pageOptions
    @options = options

    @baseUrl = URL.parse baseUrl
    # this is allows us to do ghetto url comparisons with links in the pages
    delete @baseUrl.fragment
    
    # set up crawling
    @queue = []
    @visited = {}
    @enqueuedDedup = {}
    if @options.crawl
      @enqueue @baseUrl.fragment or "#!"

    # occasionally print debug memory things
    # TODO we seem to be leaking a little bit, but it's hard to say
    if @options.memoryDebug
      @_debugInterval = setInterval (=>
        visited = _.keys @visited
        @log "[DEBUG]", "#{visited.length} scraped"
        @log "[DEBUG]", process.memoryUsage()
      ), @options.memoryDebugInterval

    
  _filterTest: (fragment) -> (filter) ->
    if typeof filter is "string" then fragment is filter
    else fragment.match filter
    

  log: -> @options.log arguments...

  scrape: (newFragment, cb) =>
    return cb(null, null) if not @_isAllowed newFragment
    try
      @log "Scraping #{newFragment}"
      url = _.clone @baseUrl
      url.hash = newFragment
      p = new DynamicPage URL.format(url), @options.pageOptions
      p.scrape (err, html, data) =>
        return cb err if err
        if not html
          @log "Error 404: #{newFragment}"
          return cb null, null
        try
          @log "Scraped #{newFragment}: #{data.title}"
          # TODO is there anything else we can do to prevent events
          # inside the free'd window from crashing the process?
          p.free()
          p = undefined
          if @options.crawl
            @enqueue fragment for fragment in (data.fragments or [])
          @saveToFile newFragment, html, cb
        catch e then cb e
    catch e then cb e
  
  saveToFile: (fragment, content, cb) ->

    filePath = @options.fragmentToPath fragment
    filePath = @options.indexName if filePath is "" or not filePath
    filePath += @options.extension
    writePath = path.join @options.outputDir, filePath
    writeDirectory = path.dirname writePath
    mkdirp writeDirectory, (err) =>
      return cb err if err
      fs.writeFile writePath, content, "utf8", (err) -> cb err, content
  
  _isAllowed: (fragment) ->
    console.log fragment
    valid = _.all @options.includeFilters, @_filterTest(fragment) 
    return valid and not _.any @options.excludeFilters, @_filterTest(fragment)
  
  ### CRAWLING RELATED THINGS ###
  enqueue: (fragment, override=false) ->
    return false if typeof fragment isnt "string"
    # ensure hash mostly to prevent duplicates
    fragment = "#" + fragment if fragment[0] isnt "#"
    return false if @enqueuedDedup[fragment]
    if override or @_isAllowed fragment
      @queue.push fragment
      @enqueuedDedup[fragment] = 1
      @log "Enqueueing #{fragment}, queue length is #{@queue.length}"
    else return false

  shouldStopCrawling: => @queue.length is 0
  shouldCrawl: (fragment) => !(@visited[fragment])

  processNextFragment: (cb) =>
    fragment = @queue.shift()
    return cb null if not fragment or not @shouldCrawl fragment
    @visited[fragment] = true
    @scrape fragment, cb

  # called automatically when a fragment is enqueued
  crawl: ->
    @log "Starting to crawl"
    async.until @shouldStopCrawling, @processNextFragment, (err) =>
      if err
        @log "Crawling error!"
        console.error err
        throw err
      else
        @log "Done crawling for now"
  

module.exports = Scraper
