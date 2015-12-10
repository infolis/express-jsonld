# ## JsonLdMiddleware
JsonLD       = require 'jsonld'
JsonldRapper = require 'jsonld-rapper'
Async        = require 'async'
Accepts      = require 'accepts'
ChildProcess = require 'child_process'

log = require('./log')(module)

_make_error = (statusCode, msg, cause) ->
	err = {}
	err.msg = msg
	err.statusCode = statusCode
	err.cause = cause if cause
	log.error 'Express-JSONLD error:', err
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
		@htmlView or= null
		if @htmlFormat not of JsonldRapper.SUPPORTED_OUTPUT_TYPE
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
				if ret of JsonldRapper.JSONLD_PROFILE
					ret = JsonldRapper.JSONLD_PROFILE[ret]
		return ret

	# <h3>handleJsonLd</h3>
	handleJsonLd: (req, res, next) ->
		profile = @detectJsonLdProfile(req)
		@jsonldRapper.convert req.jsonld, 'jsonld', 'jsonld', {profile}, (err, body) ->
			if err
				return next _make_error(500,  "JSON-LD error restructuring error", err)
			res.statusCode or= 200
			res.setHeader 'Content-Type', 'application/ld+json'
			return res.end JSON.stringify(body, null, 2)

	# TODO Decide a proper output format for HTML -- prettified JSON-LD? Turtle?
	handleHtml : (req, res, next) ->
		htmlFormat = req.query.format
		htmlFormat or= @htmlFormat
		htmlFormat = htmlFormat.replace(' ', '+')
		if req.query.profile
			htmlFormat = "application/ld+json; q=1, profile=\"#{req.query.profile}\""
		_sendHTML = (err, body) =>
			if err
				return next _make_error(406, "Unsupported format '#{htmlFormat}': #{err}")
			if typeof body is 'object'
				body = JSON.stringify(body, null, 2)
			res.setHeader 'Content-Type', 'text/html'
			res.statusCode or= 200
			if @htmlView
				return res.render @htmlView, {
					format: htmlFormat
					profile: profile
					title: req.path
					rdf:body
				}
			html = """
			<html>
				<body>
					<pre>
#{body.replace(/&/g, '&amp;').replace(/>/g, '&gt;').replace(/</g, '&lt;')} </pre>
				</body>
			</html>
			"""
			return res.send html
		req.headers['accept'] = htmlFormat
		try
			[_, outputType] = @_getAcceptType(req)
			profile = @detectJsonLdProfile(req)
		catch e
			msg = "format '#{htmlFormat}' is not supported! Please change it or leave it undefined: #{e}"
			return next _make_error(406, msg) 
		if outputType is 'jsonld'
			return @jsonldRapper.convert req.jsonld, 'jsonld', 'jsonld', {profile: profile}, _sendHTML
		# else if outputType is 'html'
		#     return @handleRdf(req, res, next)
		return @_toRdf req, res, next, _sendHTML

	# <h3>handleRdf</h3>
	# Need to convert JSON-LD to N-Quads
	handleRdf : (req, res, next) ->
		@_toRdf req, res, next, (err, converted) ->
			if err
				return next err
			return res.send converted

	_toRdf: (req, res, next, cb) ->
		try
			[matchingType, outputType] = @_getAcceptType(req)
		catch e
			return cb e
		JsonLD.toRDF req.jsonld, {expandContext: @jsonldRapper.curie.namespaces(), format: "application/nquads"}, (err, nquads) =>
			if err
				return cb _make_error(500,  "Failed to convert JSON-LD to RDF", err)
			@jsonldRapper.convert nquads, 'nquads', outputType, (err, converted) ->
				if err
					return cb err
				res.statusCode or= 200
				res.setHeader 'Content-Type', matchingType
				return cb null, converted

	_getAcceptType : (req) ->
		matchingType = Accepts(req).type(Object.keys JsonldRapper.SUPPORTED_OUTPUT_TYPE)
		unless matchingType
			throw _make_error(406, "Incompatible media type found for #{req.header 'accept'}")
		return [matchingType, JsonldRapper.SUPPORTED_OUTPUT_TYPE[matchingType]]

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
				return next _make_error(500, 'No JSON-LD payload in the request, nothing to do')

			# To make qualified content negotiation, an 'Accept' header is required
			# TODO This is too strict and should be lifted before usage in
			# production, i.e. just send JSON-LD
			if 'accept' not of req.headers
				req.headers['accept'] = 'application/json'

			try
				[matchingType, outputType] = @_getAcceptType(req)
			catch err
				return next err

			log.silly 'Accept: ', [matchingType, outputType]
			switch outputType
				when 'jsonld' then return @handleJsonLd(req, res, next)
				when 'html'   then return   @handleHtml(req, res, next)
				else               return    @handleRdf(req, res, next)

#ALT: test/middleware.coffee
