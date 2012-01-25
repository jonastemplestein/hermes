Hermes = require "./index"
cfg = require("../config/load_config")()
URL = require "url"
amqp = require "amqp"
async = require "async"

port = cfg.frontend_server.port
port = undefined if port is 80
baseUrl = URL.format
  hostname: cfg.frontend_server.host
  port: port
  pathname: cfg.frontend_server.path
  protocol: cfg.frontend_server.protocol

scraper = new Hermes.Scraper baseUrl, 
  excludeFilters: [/^#*\/notifications/]
  memoryDebug: true
  memoryDebugInterval: 60000
  pageOptions:
    showBrowserLog: false

buildOnDemand = (fragment, cb) ->
  scraper.scrape "#!#{fragment}", (err, html) =>
    cb err, html

s = new Hermes.Server
  buildOnDemandFn: buildOnDemand

s.listen cfg.seo_server.port
    
rerender = (queue, message) ->
  switch message.type
    when "user" then fragment = "/#{message.short_name}"
    when "category" then fragment = "/categories/#{message.short_name}"
    when "story" then fragment = "/story/#{message.story_id}"
  console.log "Received a rerender message"
  console.log message
  console.log "Rendering fragment #{fragment}"
  scraper.scrape "#!#{fragment}", (err, html) =>
    console.error err if err
    queue.shift()

# listen for rebuild instructions on rabbitmq as well
connection = amqp.createConnection
  host: cfg.amqp.host 
  port: cfg.amqp.port
  login: cfg.amqp.login
  password: cfg.amqp.password
  vhost: cfg.amqp.vhost

exchange = "amq.topic"
queue = null

# TODO clean up error handling, this implementation eats errors ;)
# If something breaks, it's jonas' fault
async.series
  
  "wait for connection": (done) ->
    connection.on "ready", -> done()
  
  "wait for exchange": (done) ->
    exchange = connection.exchange cfg.amqp.hermes_exchange,
      type: 'topic'
      durable: true
      autoDelete: false
    exchange.on "open", -> done()

  "wait for queue": (done) ->
    queue = connection.queue "seo_renderer",
      autoDelete: false,
      durable: true
    queue.on "open", -> done()

  "add binding": (done) ->
    queue.bind exchange, "rerender"
    queue.on "queueBindOk", -> done()

  "subscribe to queue": (done) ->
    queue.subscribe
      ack: true
    , (message) -> rerender queue, arguments...
    done()

, (err) ->
  if err
    console.error "An error happened :("
    console.log err
    throw err
