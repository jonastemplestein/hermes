# Crawl dynamic ajax webapps with hermes

Hermes allows you to write dynamic web apps with public content and have them
indexed by search engines regardless of how you wrote your client.

This is achieved by crawling your own page using jsdom.

In contrast to other similar solutions (backbone-everywhere comes to mind),
Hermes wants to be more generic and most importantly reliable and fast.
Rendering an AJAX page takes time and Google doesn't like that.

Hermes saves all created pages as static HTML and serves them super fast and
oldschool.

Hermes comes with a server that exposes crawled hash fragments as
?_escaped_fragment_=<path>.


# Status

This repository contains three classes.

`Hermes.DynamicPage` is the core. It can fetch and execute arbitrary websites
(unless jsdom crashes)

`Hermes.Scraper` builds on `Hermes.DynamicPage` and will eventually facilitate
crawling your own site.

`Hermes.Server` reads static files from a directory and serves them on a
?_escaped_fragment_ endpoint.

There's an example file example.coffee that shows how to hook up a scraper to a
server and rabbitmq updating pages either as they are requested or as updates
from rabbitmq come. This is taken from live code, I'll modify it to actually
run standalone later

For more info, read the sourcecode.

# Gotchas

This turned out to be harder than I hoped. No wonder Google doesn't care to
execute all that JS themselves.

All the rest of this document describes in what ways this software is
incomplete.

# WARNINGS/NOTES/INCOMPATIBILITIES

Most of this applies to sites that use jQuery. This is in no particular order.

 - `page.free()` doesn't seem to get rid of everything running in the page's
   event loop. Sometimes you'll get a nasty getGlobal() called after dispose()
   in contextify.cc ... I'd really like to figure this one out

 - jQuery: cssHooks cause some trouble. I disabled them and turned effects off:
   `$.fx.off = true; $.cssHooks = {};`

 - .removeAttribute() doesn't seem to be implemented in jsdom

 - Wild javascript is ... wild. I wouldn't attempt to scrape live content
   scripts that I have no control over unless I'm willing to put in the time to
   patch jsdom to work with those scripts (instead of just patching the script
   itself)

 - I have no idea how things like onclick="someFunction()" etc work with clicks
   in the simulated DOM. The same goes for all similar

 - I have no idea how search engines deal with JS these days. Just in case they
   try to run it I structured my site so that the generated html doesn't
   throw javascript errors all around and still includes the original
   javascript tags. I also set up my application to still work even if the
   DOM is already filled up with content. This may or may not be important.

 - Geometry-related code probably doesn't behave well. I'd disable it just in
   case.

 - Here's the output of `grep -R NOT_IMPLEMENTED .` in jsdom. This is (and
   fx/design related code) represents a large class of errors you'll see.

        ./lib/jsdom/browser/index.js:    this.location.reload = NOT_IMPLEMENTED(this);
        ./lib/jsdom/browser/index.js:    this.location.replace = NOT_IMPLEMENTED(this);
        ./lib/jsdom/browser/index.js:    alert: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    blur: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    confirm: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    createPopup: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    focus: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    moveBy: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    moveTo: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    open: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    print: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    prompt: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    resizeBy: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    resizeTo: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    scroll: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    scrollBy: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    scrollTo: NOT_IMPLEMENTED(),
        ./lib/jsdom/browser/index.js:    Image : NOT_IMPLEMENTED()

# TODO/nice to have

 - a integrated debugger/repl that executes code in the context of the scraped
   page would help troubleshoot jsdom compatibility issues

 - scale out over multiple cores

 - more structured/useful logging

 - hermes server and crawler binaries that read `hermes.json` and sets up a
   server and crawler with sensible defaults. Ideally the server would defer to
   the crawler to render missing pages without them being in the same process.

 - crawler that keeps track of ages of all pages and can enforce a maximum age.

 - better error handling all around (server response errors, memor
 
 - make sure there's no memory leakage and no way the crawler or server 

 - removing all TODOs from the code



