# ## JsonLdMiddleware
JsonLD       = require 'jsonld'
JsonldRapper = require 'jsonld-rapper'
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

module.exports = class ExpressJSONLD

	constructor : (opts) ->
		opts or= {}
		# <h3>Options</h3>
		@[k] = v for k,v of opts
		if not @jsonldRapper
			throw new Error("Must set 'jsonldRapper' for ExpressJSONLD")

		@htmlFormat or= 'text/html'
		if not JsonldRapper.SUPPORTED_OUTPUT_TYPE[@htmlFormat]
			throw new Error("htmlFormat '#{@htmlFormat}' is not supported! Please change it or leave it undefined")


		# Context Link to be sent out as HTTP header (default: none)
		@contextLink or= null
		# Context object (default: none)
		@context     or= {}
		@profile     or= JsonldRapper.JSONLD_PROFILE.COMPACTED

	# <h3>detectJsonLdProfile</h3>
	detectJsonLdProfile: (req) ->
		ret = @profile
		acc = req.header('Accept')
		if acc
			requestedProfile = acc.match /profile=\"([^"]+)\"/
			if requestedProfile and requestedProfile[1]
				ret = requestedProfile[1]
		return ret

	# <h3>handleJsonLd</h3>
	handleJsonLd: (req, res, next) ->
		profile = @detectJsonLdProfile(req)
		@jsonldRapper.convert req.jsonld, 'jsonld', 'jsonld', {profile}, (err, body) ->
			if err
				return next _error(500,  "JSON-LD error restructuring error", err)
			res.statusCode or= 200
			res.setHeader 'Content-Type', 'application/ld+json'
			return res.end JSON.stringify(body, null, 2)

	# TODO Decide a proper output format for HTML -- prettified JSON-LD? Turtle?
	handleHtml : (req, res, next) ->
		_sendHTML = (err, body) ->
			res.statusCode or= 200
			res.setHeader 'Content-Type', 'text/html'
			html = """
			<html>
			<body>
			<pre>
			#{body.replace(/&/g, '&amp;').replace(/>/g, '&gt;').replace(/</g, '&lt;')}
			</pre>
			</body>
			</html>
			"""
			return res.send html
		htmlFormat = req.query.format
		htmlFormat or= @htmlFormat
		htmlFormat = htmlFormat.replace(' ', '+')
		if not JsonldRapper.SUPPORTED_OUTPUT_TYPE[htmlFormat]
			return next _error 400, "format '#{htmlFormat}' is not supported! Please change it or leave it undefined"
		req.headers['accept'] = htmlFormat
		switch JsonldRapper.SUPPORTED_OUTPUT_TYPE[htmlFormat]
			when 'jsonld'
				return @jsonldRapper.convert req.jsonld, 'jsonld', 'jsonld', {profile: 'expand'}, _sendHTML
			when 'html'
				return @handleRdf(req, res, next)
			else
				return @_toRdf req, res, _sendHTML

#ALT: test/middleware.coffee
		return @handleRdf(req, res, next)
		# return res.send "<pre>" + JSON.stringify(req.jsonld, null, 2) + '</pre>' # TODO

	# <h3>handleRdf</h3>
	# Need to convert JSON-LD to N-Quads
	handleRdf : (req, res, next) ->
		@_toRdf req, res, (err, converted) ->
			if err
				return next err
			return res.send converted

	_toRdf: (req, res, cb) ->
		matchingType = Accepts(req).types(Object.keys JsonldRapper.SUPPORTED_OUTPUT_TYPE)
		outputType = JsonldRapper.SUPPORTED_OUTPUT_TYPE[matchingType]
		JsonLD.toRDF req.jsonld, {expandContext: @jsonldRapper.curie.namespaces(), format: "application/nquads"}, (err, nquads) =>
			if err
				return cb _error(500,  "Failed to convert JSON-LD to RDF", err)
			@jsonldRapper.convert nquads, 'nquads', outputType, (err, converted) ->
				if err
					return cb err
				res.statusCode or= 200
				res.setHeader 'Content-Type', matchingType
				return cb null, converted

	# <h3>getMiddleware</h3>
	# Return the actual middleware function
	getMiddleware : () ->

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
		return (req, res, next) =>
			if not req.jsonld
				return next _error(500, 'No JSON-LD payload in the request, nothing to do')

			# To make qualified content negotiation, an 'Accept' header is required
			# TODO This is too strict and should be lifted before usage in
			# production, i.e. just send JSON-LD
			if not req.header('Accept')
				return next _error(406, "No Accept header given")

			matchingType = Accepts(req).types(Object.keys JsonldRapper.SUPPORTED_OUTPUT_TYPE)

			if not JsonldRapper.SUPPORTED_OUTPUT_TYPE[matchingType]
				return next _error(406, "Incompatible media type found for #{req.header 'Accept'}")

			switch JsonldRapper.SUPPORTED_OUTPUT_TYPE[matchingType]
				when 'jsonld' then return @handleJsonLd(req, res, next)
				when 'html'   then return   @handleHtml(req, res, next)
				else               return    @handleRdf(req, res, next)

#ALT: test/middleware.coffee
