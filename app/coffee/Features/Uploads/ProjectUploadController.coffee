logger  = require "logger-sharelatex"
metrics = require "metrics-sharelatex"
fs      = require "fs"
Path    = require "path"
FileSystemImportManager = require "./FileSystemImportManager"
ProjectUploadManager    = require "./ProjectUploadManager"
AuthenticationController = require('../Authentication/AuthenticationController')
Settings = require "settings-sharelatex"
Errors = require "../Errors/Errors"
multer = require('multer')

upload = null

try
	upload = multer(
		dest: Settings.path.uploadFolder
		limits: fileSize: Settings.maxUploadSize
	)
catch err
	if err.message == "EEXIST"
		logger.log uploadFolder:Settings.path.uploadFolder, "dir already exists, continuing"
	else
		logger.err err:err, "caught error from multer in uploads router"

module.exports = ProjectUploadController =
	uploadProject: (req, res, next) ->
		timer = new metrics.Timer("project-upload")
		user_id = AuthenticationController.getLoggedInUserId(req)
		{originalname, path} = req.file
		name = Path.basename(originalname, ".zip")
		ProjectUploadManager.createProjectFromZipArchive user_id, name, path, (error, project) ->
			fs.unlink path, ->
			timer.done()
			if error?
				logger.error
					err: error, file_path: path, file_name: name,
					"error uploading project"
				if error.name? && error.name == 'InvalidError'
					res.status(422).json { success: false, error: req.i18n.translate(error.message) }
				else
					res.status(500).json { success: false, error: req.i18n.translate("upload_failed") }
			else
				logger.log
					project: project._id, file_path: path, file_name: name,
					"uploaded project"
				res.send success: true, project_id: project._id

	uploadFile: (req, res, next) ->
		timer = new metrics.Timer("file-upload")
		name = req.file?.originalname
		path = req.file?.path
		project_id   = req.params.Project_id
		folder_id    = req.query.folder_id
		if !name? or name.length == 0 or name.length > 150
			logger.err project_id:project_id, name:name, "bad name when trying to upload file"
			return res.send success: false
		logger.log folder_id:folder_id, project_id:project_id, "getting upload file request"
		user_id = AuthenticationController.getLoggedInUserId(req)

		FileSystemImportManager.addEntity user_id, project_id, folder_id, name, path, true, (error, entity) ->
			fs.unlink path, ->
			timer.done()
			if error?
				logger.error
					err: error, project_id: project_id, file_path: path,
					file_name: name, folder_id: folder_id,
					"error uploading file"
				res.send success: false
			else
				logger.log
					project_id: project_id, file_path: path, file_name: name, folder_id: folder_id
					"uploaded file"
				res.send success: true, entity_id: entity?._id, entity_type: entity?.type

	multerMiddleware: (req, res, next) ->
		return res.status(500).json {success: false, error: req.i18n.translate("upload_failed")} unless upload?
		upload.single('qqfile') req, res, (err) ->
			if err instanceof multer.MulterError && err.code == 'LIMIT_FILE_SIZE'
				return res.status(422).json {success: false, error: req.i18n.translate("file_too_large")}

			next(err)
