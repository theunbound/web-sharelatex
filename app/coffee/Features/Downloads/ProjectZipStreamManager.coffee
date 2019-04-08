archiver = require "archiver"
async    = require "async"
logger   = require "logger-sharelatex"
ProjectEntityHandler = require "../Project/ProjectEntityHandler"
ProjectGetter = require('../Project/ProjectGetter')
FileStoreHandler = require("../FileStore/FileStoreHandler")

module.exports = ProjectZipStreamManager =
	createZipStreamForMultipleProjects: (project_ids, callback = (error, stream) ->) ->
		# We'll build up a zip file that contains multiple zip files

		archive = archiver("zip")
		archive.on "error", (err)->
			logger.err err:err, project_ids:project_ids, "something went wrong building archive of project"
		callback null, archive

		logger.log project_ids: project_ids, "creating zip stream of multiple projects"

		jobs = []
		for project_id in project_ids or []
			do (project_id) ->
				jobs.push (callback) ->
					ProjectGetter.getProject project_id, name: true, (error, project) ->
						return callback(error) if error?
						logger.log project_id: project_id, name: project.name, "appending project to zip stream"
						ProjectZipStreamManager.createZipStreamForProject project_id, (error, stream) ->
							return callback(error) if error?
							archive.append stream, name: "#{project.name}.zip"
							stream.on "end", () ->
								logger.log project_id: project_id, name: project.name, "zip stream ended"
								callback()

		async.series jobs, () ->
			logger.log project_ids: project_ids, "finished creating zip stream of multiple projects"
			archive.finalize()

	createZipStreamForMultipleProjectFolders: (project_ids, callback = (error, stream) ->) ->
		# We will *not* build up a zip file that contains other zipfiles.

		archive = archiver("zip")
		archive.on "error", (err)->
			logger.err err:err, project_ids:project_ids, "something went wrong building archive of project"
		callback null, archive

		logger.log project_ids: project_ids, "creating zip stream of multiple projects *not* in zip files"

		append = (((project_id) => (callback) =>
			ProjectGetter.getProject project_id, name: true, (error, project) =>
				return callback( error ) if error?
				logger.log project_id: project_id, name: project.name, "appending project to zip stream"
				@addAllDocsToArchive project_id,
					{ archive: archive, basepath: "#{project.name}/" },
					(error) =>
						if error?
							logger.error err: error, project_id: project_id, "error adding docs to zip stream"
						@addAllFilesToArchive project_id,
							{ archive: archive, basepath: "#{project.name}/" }
							(error) ->
								if error?
									logger.error
										err: error,
										project_id: project_id,
										"error addig files to zip stream"
							callback()
		)(project_id) for project_id in project_ids or [])

		async.series append, () ->
			logger.log project_ids: project_ids, "finished creating zip of multiple projects"
			archive.finalize()
			

	createZipStreamForProject: (project_id, callback = (error, stream) ->) ->
		archive = archiver("zip")
		# return stream immediately before we start adding things to it
		archive.on "error", (err)->
			logger.err err:err, project_id:project_id, "something went wrong building archive of project"
		callback(null, archive)
		@addAllDocsToArchive project_id, archive, (error) =>
			if error?
				logger.error err: error, project_id: project_id, "error adding docs to zip stream"
			@addAllFilesToArchive project_id, archive, (error) =>
				if error?
					logger.error err: error, project_id: project_id, "error adding files to zip stream"
				archive.finalize()
	

	addAllDocsToArchive: (project_id, a, callback = (error) ->) ->
		archive = a.archive ? a
		basepath = if a.basepath? then a.basepath.replace( /\/*$/, "/") else ""
		ProjectEntityHandler.getAllDocs project_id, (error, docs) ->
			return callback(error) if error?
			jobs = []
			for path, doc of docs
				do (path, doc) ->
					path = path.replace /^\/*/, basepath
					jobs.push (callback) ->
						logger.log project_id: project_id, "Adding doc"
						archive.append doc.lines.join("\n"), name: path
						callback()
			async.series jobs, callback

	addAllFilesToArchive: (project_id, a, callback = (error) ->) ->
		archive = a.archive ? a
		basepath = if a.basepath? then a.basepath.replace( /\/*$/, "/") else ""
		ProjectEntityHandler.getAllFiles project_id, (error, files) ->
			return callback(error) if error?
			jobs = []
			for path, file of files
				do (path, file) ->
					jobs.push (callback) ->
						FileStoreHandler.getFileStream  project_id, file._id, {}, (error, stream) ->
							if error?
								logger.err err:error, project_id:project_id, file_id:file._id, "something went wrong adding file to zip archive"
								return callback(err)
							path = path.replace /^\/*/, basepath
							archive.append stream, name: path
							stream.on "end", () ->
								callback()
			async.parallelLimit jobs, 5, callback
