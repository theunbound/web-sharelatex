https = require "https"
logger = require "logger-sharelatex"

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
