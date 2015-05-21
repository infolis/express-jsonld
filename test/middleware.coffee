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

setupExpress = (doc, htmlFormat) ->
	htmlFormat or= 'text/html'
	mw = new JsonLdMiddleware(
		jsonldRapper: new JsonldRapper()
		htmlFormat: htmlFormat
	)
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

[app, mw] = setupExpress()
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
	Async.each rdfTypes, (format, done) ->
		console.log "Testing #{format}"
		[app, mw] = setupExpress(doc1)
		request(app)
			.get('/')
			.set('Accept', format)
			.end (err, res) ->
				t.notOk err, 'No error' # console.log res.text
				console.log res.body
				t.equals res.statusCode, 200, 'Returned yay'
				t.ok res.headers['content-type'].indexOf(format) > -1, 'GIGO'
				done()
	, (err) ->
		t.end()

testConneg = (t) ->
	Async.series {
		'No JSON-LD provided by the previous handler': (done) ->
			[app, mw] = setupExpress(doc1)
			request(app)
				.get('/route_doesnt_exist')
				.set('Accept', "application/ld+json")
				.end (err, res) ->
					t.notOk err, 'No internal error'
					t.equals res.status, 500, "500 Internal Server Error"
					t.ok res.text.indexOf("No JSON-LD payload") > -1, "Error message provided"
					done()
		'No Accept header, no response (TESTING only)': (done) ->
			[app, mw] = setupExpress(doc1)
			request(app)
				.get('/')
				.end (err, res) ->
					t.notOk err, 'No internal error'
					t.equals res.status, 406, "406 Unacceptable"
					t.ok res.text.indexOf("No Accept header") > -1, "Error message provided"
					done()
		'Incompatible media type': (done) ->
			[app, mw] = setupExpress(doc1)
			request(app)
				.get('/')
				.set('Accept', 'application/pdf')
				.end (err, res) ->
					t.notOk err, 'No internal error'
					t.equals res.status, 406, "406 Unacceptable"
					t.ok res.text.indexOf("Incompatible media type") > -1, "Error message provided"
					done()
		'Unsupported profile': (done) ->
			[app, mw] = setupExpress(doc1)
			request(app)
				.get('/')
				.set('Accept', 'application/ld+json; q=1, profile="http://example.com/#bad-profile"')
				.end (err, res) ->
					t.notOk err, 'No internal error'
					t.equals res.status, 500, "500 Internal Server Error"
					t.ok res.text.indexOf("Unsupported profile") > -1, "Error message provided"
					done()
	}, (err, results) ->
		t.end()

htmlExpect = {
	'text/turtle': '&lt;urn:fake:kba&gt;\n'
	'application/rdf-triples': '" .'
	# # 'application/trig'
	# 'text/vnd.graphviz'
	'application/x-turtle': '&lt;urn:fake:kba&gt;\n'
	'text/rdf+n3': '&lt;urn:fake:kba&gt;\n'
	'application/rdf+json': '"urn:fake:kba" : '
	'application/nquads': '&lt;urn:fake:kba&gt; '
	'application/rdf+xml': 'rdf:Description'
	'text/html' : 'class="triple"'
	# 'text/xml'
}
testHTML = (t) ->
	Async.each Object.keys(htmlExpect), (format, done) ->
		console.log "Testing #{format}"
		[app, mw] = setupExpress(doc1, format)
		request(app)
			.get('/')
			.set('Accept', 'text/html')
			.end (err, res) ->
				t.notOk err, 'No error' # console.log res.text
				if err
					return console.log err

				t.ok res.text.indexOf(htmlExpect[format]) > -1, "contains what is to be expected for #{format}"
				if res.text.indexOf(htmlExpect[format]) == -1
					console.log res.text

				t.equals res.statusCode, 200, 'Returned'
				t.ok res.headers['content-type'].indexOf('text/html') > -1, 'CT is HTML'
				t.ok res.text.indexOf(htmlExpect[format]) > -1, "contains what is to be expected for #{format}"
				done()
	, (err) ->
		t.end()
testHTMLparam = (t) ->
	Async.each Object.keys(htmlExpect), (format, done) ->
		console.log "Testing #{format}"
		[app, mw] = setupExpress(doc1)
		request(app)
			.get('/?format='+format)
			.set('Accept', 'text/html')
			.end (err, res) ->
				t.notOk err, 'No error' # console.log res.text
				if err
					return console.log err

				t.ok res.text.indexOf(htmlExpect[format]) > -1, "contains what is to be expected for #{format}"
				if res.text.indexOf(htmlExpect[format]) == -1
					console.log res.text

				t.equals res.statusCode, 200, 'Returned'
				t.ok res.headers['content-type'].indexOf('text/html') > -1, 'CT is HTML'
				t.ok res.text.indexOf(htmlExpect[format]) > -1, "contains what is to be expected for #{format}"
				done()
	, (err) ->
		t.end()

test "JSON-LD", testJSONLD
test "RDF", testRDF
test "HTML", testHTML
test "HTML", testHTMLparam
test "Content-Negotiation", testConneg

# ALT: src/index.coffee
