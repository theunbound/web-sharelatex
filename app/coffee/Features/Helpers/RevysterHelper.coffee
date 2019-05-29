https = require "https"
logger = require "logger-sharelatex"
TagsHandler = require "../Tags/TagsHandler"
ProjectCreationHandler = require "../Project/ProjectCreationHandler"
UserGetter = require "../User/UserGetter"
fs = require("fs").promises
path = require "path"

module.exports = RevysterHelper =

	validateEmail: (req, res, next) =>
		RevysterHelper.isEmailSubscribed req.body.email, (answer, error) ->
			if error?
				logger.log "Error getting revyster's roster."
				next(error)
			else if answer
				logger.log "Email found on revyster's roster. Registering user.", req.body.email
				next()
			else
				logger.log "Email not on revyster's roster. Sending 404.", req.body.email
				res.status 404
				.send 'message': "Den email-adresse ser ikke ud til at være tilmeldt revyster.
					Prøv en anden, eller skriv til en administrator."

	isEmailSubscribed: (email, callback ) ->
		revysterMail = 'the.bentusi@gmail.com'
		revysterPass = 'evogex'
		addressArray = []

		queryBody = 'language=en&roster-email=' +
			revysterMail.replace('@', '%40') +
			'&roster-pw=' +
			revysterPass +
			'&SubscriberRoster=Visit+Subscriber+List'
		options =
			hostname: 'mailman.nbi.ku.dk'
			path: '/mailman/roster/revyster'
			method: 'POST'
			headers:
				'Content-Type': 'application/x-www-form-urlencoded'
				'Content-Length': Buffer.byteLength(queryBody)
		dataBuffer = []
		bufferSide = 0
		
		findAddresses = () ->
			otherSide = if bufferSide == 0 then 1 else 0
			matches =
			if dataBuffer[ otherSide ]?
				dataBuffer[ otherSide ].concat dataBuffer[ bufferSide ]
			else dataBuffer[ bufferSide ]
			regexp = /<a href="..\/options\/revyster\/([^"]*)--at--([^"]*)">/g
			foundAddresses = while (matchArr = regexp.exec(matches))?
				matchArr[1] + "@" + matchArr[2]
		
			listAddresses = (address) ->
				addressArray.push( address ) if address not in addressArray
			listAddresses address for address in foundAddresses
			bufferSide = otherSide

		req = https.request options, (res) ->
			res.on 'data', (chunk) ->
				dataBuffer[bufferSide] = chunk.toString()
				findAddresses()
			res.on 'end', () ->
				if 200 <= res.statusCode < 300
					findAddresses()
					callback email in addressArray
				else
					callback null, res.headers
			res.on 'error', (error) ->
				# something
				callback null, error

		logger.log "Calling " + options.hostname + options.path + " for revyster's roster."
		req.write queryBody
		req.end

	initDb: () ->
		parachute = Error "initDb parachute"
		userId = ""
		callbackToPromise = (funcWithCallback, params...) ->
			new Promise (resolve, reject) ->
				funcWithCallback.apply null, [params..., (err, outputs...) ->
					return reject err if err?
					resolve [outputs...]
				]
		asyncGetUser = (query, projection) ->
			new Promise (resolve, reject) ->
				UserGetter.getUser query, projection, (err, user) ->
					return reject err if err?
					resolve user
		asyncGetAllTags = (user_id) ->
			new Promise (resolve, reject) ->
				TagsHandler.getAllTags user_id, (err, allTags, groupedByProject) ->
					return reject err if err?
					resolve [allTags, groupedByProject]
		createSingleDocumentProject = (docName) ->
			# returns Promise -> project
			# We look for docs in /app/templates/project_files
			docPath = path.resolve( __dirname + "/../../../templates/project_files/#{docName}")
			logger.log docPath: docPath
			docLines = fs.readFile docPath, 'utf8'
				.then (doc) ->
					doc.split '\n'

			newProject = callbackToPromise ProjectCreationHandler.createBlankProject, userId, docName.replace ".tex", ""
			logger.log docLines: typeof docLines, newProject: typeof newProject, "createSingleProjectDocument creating root doc."
			Promise.all [docLines, newProject]
				.then ([docLines, [newProject]]) ->
					callbackToPromise ProjectCreationHandler._createRootDoc, newProject, userId, docLines, docName
				.catch (error) -> logger.err error: error, stError: error.toString()

		logger.log "Performing database initialisation for Revy-use."
		callbackToPromise UserGetter.getUser, {isAdmin: true}, {}
			.then ([user]) -> 	# callbackToPromise returns an array, which gets destructured by the square bracket.
				unless user?
					logger.log "No admin user to own anything yet. Skipping initialisation."
					throw parachute
				userId = user._id.toString()
				asyncGetAllTags 1
			.then (tags) ->
				tagNames = (tag.name for tag in tags[0])
				logger.log tagNames: tagNames, "Found tags."
				taskArray = []
				unless "Kompilering" in tagNames
					logger.log tagNames: tagNames, "Tag 'Kompilering' not found. Creating."
					taskArray.push( callbackToPromise( TagsHandler.createTag, userId, "Kompilering" )
						.then ([tag]) ->
							logger.log newTag: tag, "New tag"
							Promise.all [tag, createSingleDocumentProject "revy.sty"]
						.then ([tag, [project]]) ->
							logger.log userId: userId, tagId: tag._id, project: project, "New project"
							callbackToPromise TagsHandler.addProjectToTag, userId, tag._id, project._id
					)
				unless "Skabeloner" in tagNames
					logger.log tagNames: tagNames, "Tag 'Skabeloner' not found. Creating."
					taskArray.push( callbackToPromise TagsHandler.createTag, userId, "Skabeloner"
						.then ([tag]) -> Promise.all (
							(createSingleDocumentProject docName
								.then ([project]) ->
									logger.log tag: tag, docName: docName, "Adding to tag"
									callbackToPromise TagsHandler.addProjectToTag, userId, tag._id, project._id
							) for docName in ["Sang.tex", "Sketch.tex"]
							# Have I gone mad!? Probably...
						)
					)
				if taskArray.length == 0
					logger.log "No init seems to need doing."
				return Promise.all taskArray
			.catch (error) ->
				unless error == parachute
					# Just let it go?
					logger.err error: error, stError: error.toString(), "RevysterInitDb"
