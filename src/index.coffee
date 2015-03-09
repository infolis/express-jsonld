# ## JsonLdMiddleware
JsonLD       = require 'jsonld'
JsonLD2RDF	 = require 'jsonld-rapper'
Async        = require 'async'
Accepts      = require 'accepts'
ChildProcess = require 'child_process'

_error = (statusCode, msg, cause) ->
	err = new Error(msg)
	err.msg = msg
	err.statusCode = statusCode
	err.cause = cause if cause
	return err


###

Middleware for Express that handles Content-Negotiation and sends the
right format to the client, based on the JSON-LD representation of the graph.

###

JsonLdMiddleware = (options) ->

	# <h3>Options</h3>
	options = options                         || {}
	# Context Link to be sent out as HTTP header (default: none)
	options.contextLink = options.contextLink || null
	# Context object (default: none)
	options.context = options.context         || {}
	# Options for jsonld.expand
	options.expand = options.expand           || {expandContext: options.context}
	# Options for jsonld.compact
	options.compact =  options.compact        || {expandContext: options.context, compactArrays: true}
	# Options for jsonld.flatten
	options.flatten =  options.flatten        || {expandContext: options.context}
	j2r = options.j2r                 || options.jsonLD2RDF || new JsonLD2RDF()

	# <h3>detectJsonLdProfile</h3>
	detectJsonLdProfile = (req) ->
		ret = options.profile
		acc = req.header('Accept')
		if acc
			requestedProfile = acc.match /profile=\"([^"]+)\"/
			if requestedProfile and requestedProfile[1]
				ret = requestedProfile[1]
		return ret

	# <h3>handleJsonLd</h3>
	handleJsonLd = (req, res, next) ->
		profile = detectJsonLdProfile(req)
		j2r.convert req.jsonld, 'jsonld', 'jsonld', {profile}, (err, body) ->
			if err
				return next _error(500,  "JSON-LD error restructuring error", err)
			res.statusCode = 200
			res.setHeader 'Content-Type', 'application/ld+json'
			return res.end JSON.stringify(body, null, 2)

	# TODO Decide a proper output format for HTML -- prettified JSON-LD? Turtle?
	handleHtml = (req, res, next) ->
		res.statusCode = 200
		res.setHeader 'Content-Type', 'text/html'
		return res.send "<pre>" + JSON.stringify(req.jsonld) + '</pre>' # TODO

	# <h3>handleRdf</h3>
	# Need to convert JSON-LD to N-Quads
	handleRdf = (req, res, next) ->
		matchingType = Accepts(req).types(Object.keys j2r.SUPPORTED_OUTPUT_TYPE)
		outputType = j2r.SUPPORTED_OUTPUT_TYPE[matchingType]
		JsonLD.toRDF req.jsonld, {expandContext: options.context, format: "application/nquads"}, (err, nquads) ->
			if err
				return next _error(500,  "Failed to convert JSON-LD to RDF", err)
			j2r.convert nquads, 'nquads', outputType, (err, converted) ->
				if err
					return next err
				res.statusCode = 200
				res.setHeader 'Content-Type', matchingType
				res.send converted

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

		matchingType = Accepts(req).types(Object.keys j2r.SUPPORTED_OUTPUT_TYPE)

		if not j2r.SUPPORTED_OUTPUT_TYPE[matchingType]
			return next _error(406, "Incompatible media type found for #{req.header 'Accept'}")

		switch j2r.SUPPORTED_OUTPUT_TYPE[matchingType]
			when 'jsonld' then return handleJsonLd(req, res, next)
			when 'html'   then return   handleHtml(req, res, next)
			else               return    handleRdf(req, res, next)

	# Return
	return {
		handle: handle
	}

# ## Module exports	
module.exports = JsonLdMiddleware

#ALT: test/middleware.coffee
