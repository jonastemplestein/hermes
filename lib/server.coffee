_ = require "underscore"
async = require "async"
connect = require "connect"
URL = require "url"
fs = require "fs"
path = require "path"


###
  connect-based HTTP server that can respond to ?_escaped_fragment=<fragment>
  requests and has a hook for on-demand generation.
###
class Server

  defaultOptions:

    # log fn, feel free to override
    log: -> console.log new Date().toISOString(), arguments...
    
    # Prop in a function here that takes a hash token and cb(err, html) and
    # comes back with the html
    buildOnDemandFn: undefined

    # Directory relative to `pwd` where the static files are at
    dir: "./static"
    
    # Given a fragment as per the AJAX crawling spec (the part after #!) this
    # function must return the relative path and basename within `baseDir`
    fragmentToPath: _.identity

    # Basename for empty fragment
    indexName: "index"

    # Extension of static files
    extension: ".html"

  constructor: (@options={}) ->
    _.defaults @options, @defaultOptions
    @server = connect.createServer()
    @server.use connect.logger()
    @server.use connect.query()
    @server.use @deliver
    @server.use connect.errorHandler
      stack: true
      message: true
      dump: true

  deliver: (req, res, next) =>
    fragment = req.query._escaped_fragment_
    if typeof fragment is "undefined"
      res.writeHead 400,
        "Content-Type": "text/plain"
      return res.end "This server expects a _escaped_fragment_ query parameter"
    if not fragment or fragment is "/" or fragment.match /^\s*$/
      fragment = @options.indexName
    filePath = path.normalize @options.fragmentToPath fragment
    filePath += @options.extension
    filePath = path.join @options.dir, filePath
    req.fragment = fragment
    fs.readFile filePath, "utf8", (err, html) =>
      if err?.code is "ENOENT" then return @handle404 req, res, next
      else if err then return next err
      res.writeHead 200,
        "Content-Type": "text/html"
      return res.end html 

  handle404: (req, res, next) ->
    if not req.fragment
      return next new Error "handle404 needs req.fragment to be set"
    if not @options.buildOnDemandFn
      res.writeHead 404
      res.end()
    else
      @options.buildOnDemandFn req.fragment, (err, html) =>
        return next err if err
        if not html
          res.writeHead 404
          res.end()
        else
          res.writeHead 200,
            "Content-Type": "text/html"
          return res.end html 

  log: -> @options.log arguments...

  listen: (port, host) ->
    @log "Starting server on port #{host}:#{port}"
    @server.listen port, host

module.exports = Server

