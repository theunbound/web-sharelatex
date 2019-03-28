sinon = require('sinon')
chai = require('chai')
should = chai.should()
expect = chai.expect
modulePath = "../../../../app/js/Features/Uploads/ProjectUploadController.js"
SandboxedModule = require('sandboxed-module')
MockRequest = require "../helpers/MockRequest"
MockResponse = require "../helpers/MockResponse"
Errors = require("../../../../app/js/Features/Errors/Errors")

describe "ProjectUploadController", ->
	beforeEach ->
		@req = new MockRequest()
		@res = new MockResponse()
		@user_id = "user-id-123"
		@metrics =
			Timer: class Timer
				done: sinon.stub()
		@AuthenticationController =
			getLoggedInUserId: sinon.stub().returns(@user_id)

		@ProjectUploadController = SandboxedModule.require modulePath, requires:
			"./ProjectUploadManager" : @ProjectUploadManager = {}
			"./FileSystemImportManager" : @FileSystemImportManager = {}
			"logger-sharelatex" : @logger = {log: sinon.stub(), error: sinon.stub(), err:->}
			"metrics-sharelatex": @metrics
			'../Authentication/AuthenticationController': @AuthenticationController
			"fs" : @fs = {}

	describe "uploadProject", ->
		beforeEach ->
			@path = "/path/to/file/on/disk.zip"
			@name = "filename.zip"
			@req.file =
				path: @path
				originalname: @name
			@req.session =
				user:
					_id: @user_id
			@project =
				_id: @project_id = "project-id-123"

			@fs.unlink = sinon.stub()

		describe "successfully", ->
			beforeEach ->
				@ProjectUploadManager.createProjectFromZipArchive =
					sinon.stub().callsArgWith(3, null, @project)
				@ProjectUploadController.uploadProject @req, @res

			it "should create a project owned by the logged in user", ->
				@ProjectUploadManager
					.createProjectFromZipArchive
					.calledWith(@user_id)
					.should.equal true

			it "should create a project with the same name as the zip archive", ->
				@ProjectUploadManager
					.createProjectFromZipArchive
					.calledWith(sinon.match.any, "filename", sinon.match.any)
					.should.equal true

			it "should create a project from the zip archive", ->
				@ProjectUploadManager
					.createProjectFromZipArchive
					.calledWith(sinon.match.any, sinon.match.any, @path)
					.should.equal true

			it "should return a successful response to the FileUploader client", ->
				expect(@res.body).to.deep.equal
					success: true
					project_id: @project_id

			it "should record the time taken to do the upload", ->
				@metrics.Timer::done.called.should.equal true

			it "should output a log line", ->
				@logger.log
					.calledWith(sinon.match.any, "uploaded project")
					.should.equal true

			it "should remove the uploaded file", ->
				@fs.unlink.calledWith(@path).should.equal true

		describe "when ProjectUploadManager.createProjectFromZipArchive fails", ->
			beforeEach ->
				@ProjectUploadManager.createProjectFromZipArchive =
					sinon.stub().callsArgWith(3, new Error("Something went wrong"), @project)
				@ProjectUploadController.uploadProject @req, @res

			it "should return a failed response to the FileUploader client", ->
				expect(@res.body).to.deep.equal JSON.stringify({ success: false, error: "upload_failed" })

			it "should output an error log line", ->
				@logger.error
					.calledWith(sinon.match.any, "error uploading project")
					.should.equal true

		describe "when ProjectUploadManager.createProjectFromZipArchive reports the file as invalid", ->
			beforeEach ->
				@ProjectUploadManager.createProjectFromZipArchive =
					sinon.stub().callsArgWith(3, new Errors.InvalidError("zip_contents_too_large"), @project)
				@ProjectUploadController.uploadProject @req, @res

			it "should return the reported error to the FileUploader client", ->
				expect(@res.body).to.deep.equal JSON.stringify({ success: false, error: "zip_contents_too_large" })

			it "should return an 'unprocessable entity' status code", ->
				expect(@res.statusCode).to.equal 422

			it "should output an error log line", ->
				@logger.error
					.calledWith(sinon.match.any, "error uploading project")
					.should.equal true

	describe "uploadFile", ->
		beforeEach ->
			@project_id = "project-id-123"
			@folder_id = "folder-id-123"
			@path = "/path/to/file/on/disk.png"
			@name = "filename.png"
			@req.file =
				path: @path
				originalname: @name
			@req.session =
				user:
					_id: @user_id
			@req.params =
				Project_id: @project_id
			@req.query =
				folder_id: @folder_id
			@fs.unlink = sinon.stub()


		describe "successfully", ->

			beforeEach ->
				@entity =
					_id : "1234"
					type: 'file'
				@FileSystemImportManager.addEntity = sinon.stub().callsArgWith(6, null, @entity)
				@ProjectUploadController.uploadFile @req, @res

			it "should insert the file", ->
				@FileSystemImportManager.addEntity
					.calledWith(@user_id, @project_id, @folder_id, @name, @path)
					.should.equal true

			it "should return a successful response to the FileUploader client", ->
				expect(@res.body).to.deep.equal
					success: true
					entity_id: @entity._id
					entity_type: 'file'

			it "should output a log line", ->
				@logger.log
					.calledWith(sinon.match.any, "uploaded file")
					.should.equal true

			it "should time the request", ->
				@metrics.Timer::done.called.should.equal true

			it "should remove the uploaded file", ->
				@fs.unlink.calledWith(@path).should.equal true

		describe "when FileSystemImportManager.addEntity returns an error", ->
			beforeEach ->
				@FileSystemImportManager.addEntity = sinon.stub()
					.callsArgWith(6, new Error("Sorry something went wrong"))
				@ProjectUploadController.uploadFile @req, @res

			it "should return an unsuccessful response to the FileUploader client", ->
				expect(@res.body).to.deep.equal
					success: false

			it "should output an error log line", ->
				@logger.error
					.calledWith(sinon.match.any, "error uploading file")
					.should.equal true

		describe "with a bad request", ->

			beforeEach ->
				@req.file.originalname = ""
				@ProjectUploadController.uploadFile @req, @res

			it "should return a a non success response", ->
				expect(@res.body).to.deep.equal
					success: false
