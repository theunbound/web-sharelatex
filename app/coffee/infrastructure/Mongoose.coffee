mongoose = require('mongoose')
Settings = require 'settings-sharelatex'
logger = require('logger-sharelatex')
RevysterHelper = require '../Features/Helpers/RevysterHelper'

mongoose.connect(Settings.mongo.url, {
	server: {poolSize: 10},
	config: {autoIndex: false}
})

mongoose.connection.on 'connected', () ->
	logger.log {url:Settings.mongo.url}, 'mongoose default connection open'
	RevysterHelper.initDb()

mongoose.connection.on 'error', (err) ->
	logger.err err:err, 'mongoose error on default connection';

mongoose.connection.on 'disconnected', () ->
	logger.log 'mongoose default connection disconnected'

module.exports = mongoose
