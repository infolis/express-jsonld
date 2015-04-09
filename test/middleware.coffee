Async   = require 'async'
util    = require 'util'
test    = require 'tape'
express = require 'express'
request = require 'supertest'
jsonld  = require 'jsonld'
JsonldRapper = require('jsonld-rapper')

JsonLdMiddleware = require('../src')
DEBUG=false
# DEBUG=true

doc1 = {
	'@context': {
		"foaf": "http://xmlns.com/foaf/0.1/"
	},
	'@id': 'urn:fake:kba'
	'foaf:firstName': 'Konstantin'
}

setupExpress = (doc, mwOptions) ->
	mw = new JsonLdMiddleware()
	# console.log mw.handle.toString()
	app = express()
	app.get '/', (req, res, next) ->
		req.jsonld = doc 
		next()

	app.use mw.getMiddleware()
	app.use (err, req, res, next) ->
		err or= new Error('NO ERROR BUT UNHANDLED BAD BAD BAD')
		DEBUG and console.log {error: JSON.stringify(err, null, 2)}
		DEBUG and throw err
		res.status(err.statusCode || 500)
		# res.end JSON.stringify({error: err }, null, 2)
		res.send({error: err})
		# console.log res.headers
		# res.end "foo"
	return [app, mw]

app = null
mw = new JsonLdMiddleware()
reApplicationJsonLd = new RegExp "application/ld\\+json"

testJSONLD = (t) ->
	[app, mw] = setupExpress(doc1)
	profiles = {}
	profiles[profile] = true for __, profile of JsonldRapper.JSONLD_PROFILE
	profiles = Object.keys(profiles)
	console.log profiles
	Async.each profiles, (profile, done) ->
		request(app)
			.get('/')
			.set('Accept', "application/ld+json; q=1, profile=\"#{profile}\"") 
			.end (err, res) ->
				console.log "Profile detection for #{profile}"
				console.log res.body
				t.notOk err, 'No error'
				t.equals res.status, 200, 'Status 200'
				done()
				# t.ok reApplicationJsonLd.test(res.headers['content-type']), 'Correct Type'
				# switch profile
				#     when mw.jsonldRapper.JSONLD_PROFILE.COMPACTED
				#         jsonld.compact doc1, {}, (err, expanded) ->
				#             t.deepEquals JSON.parse(res.text), expanded, 'Correct profile is returned'
				#             t.end()
				#     when mw.jsonldRapper.JSONLD_PROFILE.FLATTENED
				#         jsonld.flatten doc1, {}, (err, expanded) ->
				#             t.deepEquals JSON.parse(res.text), expanded, 'Correct profile is returned'
				#             t.end()
				#     when mw.jsonldRapper.JSONLD_PROFILE.EXPANDED
				#         jsonld.expand doc1, {}, (err, expanded) ->
				#             t.deepEquals JSON.parse(res.text), expanded, 'Correct profile is returned'
				#             t.end()
				#     else
				#         console.error("Unknown Profile -- WTF?")
				#         t.end()
		, (err) ->
			t.end()

rdfTypes = [
	'text/turtle'
	'application/rdf-triples'
	# 'application/trig'
	'text/vnd.graphviz'
	'application/x-turtle'
	'text/rdf+n3'
	'application/rdf+json'
	'application/nquads'
	'application/rdf+xml'
	'text/xml'
]
testRDF = (t) ->
	t.beforeEach (t) ->
		[app, mw] = setupExpress(doc1)
		t.end()
	testFormat = (t, format) ->
		t.test "Testing #{format}", (t) ->
			request(app)
				.get('/')
				.set('Accept', format)
				.end (err, res) ->
					t.notOk err, 'No error' # console.log res.text
					console.log res.body
					t.equals res.statusCode, 200, 'Returned yay'
					t.ok res.headers['content-type'].indexOf(format) > -1, 'GIGO'
					t.end()
	testFormat(t, rdfType) for rdfType in rdfTypes
	t.end()

testConneg = (t) ->
	t.beforeEach (t) ->
		[app, mw] = setupExpress(doc1)
		t.end()

	t.test 'No JSON-LD provided by the previous handler', (t) ->
		request(app)
			.get('/route_doesnt_exist')
			.set('Accept', "application/ld+json")
			.end (err, res) ->
				t.notOk err, 'No internal error'
				t.equals res.status, 500, "500 Internal Server Error"
				t.ok res.text.indexOf("No JSON-LD payload") > -1, "Error message provided"
				t.end()

	t.test 'No Accept header, no response (TESTING only)', (t) ->
		request(app)
			.get('/')
			.end (err, res) ->
				t.notOk err, 'No internal error'
				t.equals res.status, 406, "406 Unacceptable"
				t.ok res.text.indexOf("No Accept header") > -1, "Error message provided"
				t.end()

	t.test 'Incompatible media type', (t) ->
		request(app)
			.get('/')
			.set('Accept', 'application/pdf')
			.end (err, res) ->
				t.notOk err, 'No internal error'
				t.equals res.status, 406, "406 Unacceptable"
				t.ok res.text.indexOf("Incompatible media type") > -1, "Error message provided"
				t.end()

	t.test 'Unsupported profile', (t) ->
		request(app)
			.get('/')
			.set('Accept', 'application/ld+json; q=1, profile="http://example.com/#bad-profile"')
			.end (err, res) ->
				t.notOk err, 'No internal error'
				t.equals res.status, 500, "500 Internal Server Error"
				t.ok res.text.indexOf("Unsupported profile") > -1, "Error message provided"
				t.end()
	t.end()

test.only "JSON-LD", testJSONLD
test "RDF", testRDF
test "Content-Negotiation", testConneg

# TODO use async to properly run tests in order

# ALT: src/index.coffee
