# ## JsonLdMiddleware
JsonLD       = require 'jsonld'
Async        = require 'async'
Accepts      = require 'accepts'
ChildProcess = require 'child_process'

###

Middleware for Express that handles Content-Negotiation and sends the
right format to the client, based on the JSON-LD representation of the graph.

###

JsonLdMiddleware = (options) ->

	# <h3>Supported Types</h3>
	# The Middleware is able to output JSON-LD in these serializations

	typeMap = [
		['application/json',        'jsonld']   # no-op
		['application/ld+json',     'jsonld']   # no-op
		['application/rdf-triples', 'ntriples'] # jsonld/nquads -> raptor/ntriples
		# ['application/trig',        'trig']     # jsonld/nquads -> raptor/trig
		['text/vnd.graphviz',       'dot']      # jsonld/nquads -> rapper/graphviz
		['application/x-turtle',    'turtle']   # jsonld/nquads -> raptor/turtle
		['text/rdf+n3',             'turtle']   # jsonld/nquads -> raptor/turtle
		['text/turtle',             'turtle']   # jsonld/nquads -> raptor/turtle
		['application/rdf+json',    'json']     # jsonld/nquads -> raptor/json
		['application/nquads',      'nquads']   # jsonld/nquads
		['application/rdf+xml',     'rdfxml']   # jsonld/nquads -> raptor/rdfxml
		['text/xml',                'rdfxml']   # jsonld/nquads -> raptor/rdfxml
		['text/html',               'html']     # jsonld/nquads -> raptor/turtle -> jade
	]
	SUPPORTED_TYPES = {}
	SUPPORTED_TYPES[type] = shortType for [type, shortType] in typeMap

	# <h3>JSON-LD profiles</h3>
	JSONLD_PROFILE = 
		COMPACTED: 'http://www.w3.org/ns/json-ld#compacted'
		FLATTENED: 'http://www.w3.org/ns/json-ld#flattened'
		EXPANDED:  'http://www.w3.org/ns/json-ld#expanded'

	# <h3>Options</h3>
	options = options                         || {}
	# Context Link to be sent out as HTTP header (default: none)
	options.contextLink = options.contextLink || null
	# Context object (default: none)
	options.context = options.context         || {}
	# Base URI for RDF serializations that require them (i.e. all of them, hence the default)
	options.baseURI = options.baseURI         || 'http://NO-BASEURI-IS-SET.tld/'
	# Default JSON-LD compaction profile to use if no other profile is requested (defaults to compacted)
	options.profile = options.profile         || JSONLD_PROFILE.COMPACTED
	# Options for jsonld.expand
	options.expand = options.expand           || {expandContext: options.context}
	# Options for jsonld.compact
	options.compact =  options.compact        || {expandContext: options.context, compactArrays: true}
	# Options for jsonld.flatten
	options.flatten =  options.flatten        || {expandContext: options.context}

	# <h3>detectJsonLdProfile</h3>
	detectJsonLdProfile = (req) ->
		ret = options.profile
		acc = req.header('Accept')
		if acc
			requestedProfile = acc.match /profile=\"([^"]+)\"/
			if requestedProfile and requestedProfile[1]
				ret = requestedProfile[1]
		return ret

	_error = (statusCode, msg, cause) ->
		err = new Error(msg)
		err.msg = msg
		err.statusCode = statusCode
		err.cause = cause if cause
		return err

	# <h3>handleJsonLd</h3>
	handleJsonLd = (req, res, next) ->
		sendJsonLD = (err, body) ->
			if err
				return next _error(500,  "JSON-LD error restructuring error", err)
			res.statusCode = 200
			res.setHeader 'Content-Type', 'application/ld+json'
			return res.end JSON.stringify(body, null, 2)
		profile = detectJsonLdProfile(req)
		switch profile
			when JSONLD_PROFILE.COMPACTED
				return JsonLD.compact req.jsonld, options.context, options.compact, sendJsonLD
			when JSONLD_PROFILE.EXPANDED
				return JsonLD.expand req.jsonld, {expandContext: options.context}, sendJsonLD
			when JSONLD_PROFILE.FLATTENED
				return JsonLD.flatten req.jsonld, options.context, sendJsonLD
			else
				# TODO make this extensible
				return next _error(500, "Unsupported profile: #{profile}")

	# TODO Decide a proper output format for HTML -- prettified JSON-LD? Turtle?
	handleHtml = (req, res, next) ->
		res.statusCode = 200
		res.setHeader 'Content-Type', 'text/html'
		return res.send "<pre>" + JSON.stringify(req.jsonld) + '</pre>' # TODO

	# <h3>handleRdf</h3>
	# Need to convert JSON-LD to N-Quads
	handleRdf = (req, res, next) ->
		matchingType = Accepts(req).types(Object.keys SUPPORTED_TYPES)
		shortType = SUPPORTED_TYPES[matchingType]
		JsonLD.toRDF req.jsonld, {expandContext: options.context, format: "application/nquads"}, (err, nquads) ->
			if err
				return next new _error(500,  "Failed to convert JSON-LD to RDF", err)

			# If nquads were requested we're done now
			if shortType is 'nquads'
				res.statusCode = 200
				res.setHeader 'Content-Type', 'application/nquads'
				return res.send nquads

			# Spawn `rapper` with a nquads parser and a serializer producing `#{shortType}`
			cmd = "rapper -i nquads -o #{shortType} - #{options.baseURI}"
			serializer = ChildProcess.spawn("rapper", ["-i", "nquads", "-o", shortType, "-", options.baseURI])
			serializer.on 'error', (err) -> 
				return next _error(500, 'Could not spawn rapper process')
			# When data is available, concatenate it to a buffer
			buf=''
			errbuf=''
			serializer.stderr.on 'data', (chunk) -> 
				errbuf += chunk.toString('utf8')
			serializer.stdout.on 'data', (chunk) -> 
				buf += chunk.toString('utf8')
			# Pipe the nquads into the process and close stdin
			serializer.stdin.write(nquads)
			serializer.stdin.end()
			# When rapper finished without error, return the serialized RDF
			serializer.on 'close', (code) ->
				if code isnt 0
					return next _error(500,  "Rapper failed to convert N-QUADS to #{shortType}", errbuf)
				res.statusCode = 200
				res.setHeader 'Content-Type', matchingType
				res.send buf

	# <h3>handle</h3>
	# Return the actual middleware function
	handle = (req, res, next) ->

		###
		The JSON-LD must be attached as 'jsonld' to the request, i.e. the handler before the JSON-LD
		middleware must do
		```coffee
		_ handler : (req, res) ->
		_ 	# do something to create/retrieve jsonld
		_ 	req.jsonld = {'@context': ...}
		_ 	next()
		```
		###
		if not req.jsonld
			return next _error(500, 'No JSON-LD payload in the request, nothing to do')

		# To make qualified content negotiation, an 'Accept' header is required
		# TODO This is too strict and should be lifted before usage in production, i.e. just send JSON-LD
		if not req.header('Accept')
			return next _error(406, "No Accept header given")

		matchingType = Accepts(req).types(Object.keys SUPPORTED_TYPES)

		if not SUPPORTED_TYPES[matchingType]
			return next _error(406, "Incompatible media type found for #{req.header 'Accept'}")

		switch SUPPORTED_TYPES[matchingType]
			when 'jsonld' then return handleJsonLd(req, res, next)
			when 'html'   then return   handleHtml(req, res, next)
			else               return    handleRdf(req, res, next)

	# Return
	return {
		handle: handle
		JSONLD_PROFILE: JSONLD_PROFILE
		SUPPORTED_TYPES: SUPPORTED_TYPES
	}

# ## Module exports	
module.exports = JsonLdMiddleware

#ALT: test/middleware.coffee
