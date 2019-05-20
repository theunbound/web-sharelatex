assert = require("chai").assert
sinon = require('sinon')
chai = require('chai')
should = chai.should()
expect = chai.expect
modulePath = "../../../../app/js/Features/FileStore/FileStoreHandler.js"
SandboxedModule = require('sandboxed-module')

describe "FileStoreHandler", ->
	beforeEach ->
		@fs =
			createReadStream : sinon.stub()
			lstat: sinon.stub().callsArgWith(1, null, {
				isFile:=> true
				isDirectory:-> return false
			})
		@writeStream =
			my:"writeStream"
			on: (type, cb)->
				if type == "response"
					cb({statusCode: 200})
		@readStream = {my:"readStream", on: sinon.stub()}
		@request = sinon.stub()
		@settings = apis:{filestore:{url:"http//filestore.sharelatex.test"}}
		@hashValue = "0123456789"
		@FileModel = class File
			constructor:(options)->
				{@name,@hash} = options
				@_id = "file_id_here"
				@rev = 0
				if options.linkedFileData?
					@linkedFileData = options.linkedFileData
		@handler = SandboxedModule.require modulePath, requires:
			"settings-sharelatex":@settings
			"request":@request
			"logger-sharelatex" : @logger = {log:sinon.stub(), err:sinon.stub()}
			"./FileHashManager" : @FileHashManager = { computeHash: sinon.stub().callsArgWith(1, null, @hashValue)}
			# FIXME: need to stub File object here
			"../../models/File" : File: @FileModel
			"fs" : @fs
		@file_args = {name: "upload-filename"}
		@file_id = "file_id_here"
		@project_id = "1312312312"
		@fsPath = "uploads/myfile.eps"
		@handler._buildUrl = sinon.stub().returns("http://filestore.stubbedBuilder.com")

	describe "uploadFileFromDisk", ->
		beforeEach ->
			@request.returns(@writeStream)

		it "should create read stream", (done)->
			@fs.createReadStream.returns
				pipe:->
				on: (type, cb)->
					if type == "open"
						cb()
			@handler.uploadFileFromDisk @project_id, @file_args, @fsPath, =>
				@fs.createReadStream.calledWith(@fsPath).should.equal true
				done()

		it "should pipe the read stream to request", (done)->
			@request.returns(@writeStream)
			@fs.createReadStream.returns
				on: (type, cb)->
					if type == "open"
						cb()
				pipe:(o)=>
					@writeStream.should.equal o
					done()
			@handler.uploadFileFromDisk @project_id, @file_args, @fsPath, =>

		it "should pass the correct options to request", (done)->
			@fs.createReadStream.returns
				pipe:->
				on: (type, cb)->
					if type == "open"
						cb()
			@handler.uploadFileFromDisk @project_id, @file_args, @fsPath, =>
				@request.args[0][0].method.should.equal "post"
				@request.args[0][0].uri.should.equal @handler._buildUrl()
				done()

		it "builds the correct url", (done)->
			@fs.createReadStream.returns
				pipe:->
				on: (type, cb)->
					if type == "open"
						cb()
			@handler.uploadFileFromDisk @project_id, @file_args, @fsPath, =>
				@handler._buildUrl.calledWith(@project_id, @file_id).should.equal true
				done()

		it 'should callback with the url and fileRef', (done) ->
			@fs.createReadStream.returns
				pipe:->
				on: (type, cb)->
					if type == "open"
						cb()
			@handler.uploadFileFromDisk @project_id, @file_args, @fsPath, (err, url, fileRef) =>
				expect(err).to.not.exist
				expect(url).to.equal(@handler._buildUrl())
				expect(fileRef._id).to.equal(@file_id)
				expect(fileRef.hash).to.equal(@hashValue)
				done()

		describe "symlink", ->
			beforeEach ->
				@fs.lstat = sinon.stub().callsArgWith(1, null, {
					isFile:=> false
					isDirectory:-> return false
				})

			it "should not read file if it is symlink", (done)->
				@handler.uploadFileFromDisk @project_id, @file_args, @fsPath, =>
					@fs.createReadStream.called.should.equal false
					done()

		describe "symlink", ->
			it "should not read file stat returns nothing", (done)->
				@fs.lstat = sinon.stub().callsArgWith(1, null, null)
				@handler.uploadFileFromDisk @project_id, @file_args, @fsPath, =>
					@fs.createReadStream.called.should.equal false
					done()

		describe "when upload fails", ->
			beforeEach ->
				@writeStream.on = (type, cb) ->
					if type == "response"
						cb({statusCode: 500})

			it 'should callback with an error', (done) ->
				@fs.createReadStream.callCount = 0
				@fs.createReadStream.returns
					pipe:->
					on: (type, cb)->
						if type == "open"
							cb()
				@handler.uploadFileFromDisk @project_id, @file_args, @fsPath, (err) =>
					expect(err).to.exist
					expect(err).to.be.instanceof Error
					expect(@fs.createReadStream.callCount).to.equal @handler.RETRY_ATTEMPTS
					done()

	describe "deleteFile", ->

		it "should send a delete request to filestore api", (done)->
			@request.callsArgWith(1, null)
			@handler.deleteFile @project_id, @file_id, (err)=>
				assert.equal err, undefined
				@request.args[0][0].method.should.equal "delete"
				@request.args[0][0].uri.should.equal @handler._buildUrl()
				done()

		it "should return the error if there is one", (done)->
			error = "my error"
			@request.callsArgWith(1, error)
			@handler.deleteFile @project_id, @file_id, (err)=>
				assert.equal err, error
				done()

		it "builds the correct url", (done)->
			@request.callsArgWith(1, null)
			@handler.deleteFile @project_id, @file_id, (err)=>
				@handler._buildUrl.calledWith(@project_id, @file_id).should.equal true
				done()

	describe "getFileStream", ->
		beforeEach ->
			@query = {}
			@request.returns(@readStream)

		it "should get the stream with the correct params", (done)->
			@handler.getFileStream @project_id, @file_id, @query, (err, stream)=>
				@request.args[0][0].method.should.equal "get"
				@request.args[0][0].uri.should.equal @handler._buildUrl()
				done()

		it "should get stream from request", (done)->
			@handler.getFileStream @project_id, @file_id, @query, (err, stream)=>
				stream.should.equal @readStream
				done()

		it "builds the correct url", (done)->
			@handler.getFileStream @project_id, @file_id, @query, (err, stream)=>
				@handler._buildUrl.calledWith(@project_id, @file_id).should.equal true
				done()

		it "should add an error handler", (done) ->
			@handler.getFileStream @project_id, @file_id, @query, (err, stream)=>
				stream.on.calledWith("error").should.equal true
				done()

		describe 'when range is specified in query', ->

			beforeEach ->
				@query = {'range': '0-10'}

			it 'should add a range header', (done) ->
				@handler.getFileStream @project_id, @file_id, @query, (err, stream)=>
					@request.callCount.should.equal 1
					headers = @request.firstCall.args[0].headers
					expect(headers).to.have.keys('range')
					expect(headers['range']).to.equal 'bytes=0-10'
					done()

			describe 'when range is invalid', ->

				['0-', '-100', 'one-two', 'nonsense'].forEach (r) =>

					beforeEach ->
						@query = {'range': "#{r}"}

					it "should not add a range header for '#{r}'", (done) ->
						@handler.getFileStream @project_id, @file_id, @query, (err, stream)=>
							@request.callCount.should.equal 1
							headers = @request.firstCall.args[0].headers
							expect(headers).to.not.have.keys('range')
							done()

	describe "copyFile", ->

		beforeEach ->
			@newProject_id = "new project"
			@newFile_id = "new file id"

		it "should post json", (done)->
			@request.callsArgWith(1, null, {statusCode: 200})

			@handler.copyFile @project_id, @file_id, @newProject_id, @newFile_id, =>
				@request.args[0][0].method.should.equal "put"
				@request.args[0][0].uri.should.equal @handler._buildUrl()
				@request.args[0][0].json.source.project_id.should.equal @project_id
				@request.args[0][0].json.source.file_id.should.equal @file_id
				done()

		it "builds the correct url", (done)->
			@request.callsArgWith(1, null, {statusCode: 200})
			@handler.copyFile @project_id, @file_id, @newProject_id, @newFile_id, =>
				@handler._buildUrl.calledWith(@newProject_id, @newFile_id).should.equal true
				done()

		it "returns the url", (done)->
			@request.callsArgWith(1, null, {statusCode: 200})
			@handler.copyFile @project_id, @file_id, @newProject_id, @newFile_id, (err, url) =>
				url.should.equal "http://filestore.stubbedBuilder.com"
				done()

		it "should return the err", (done)->
			error = "errrror"
			@request.callsArgWith(1, error)
			@handler.copyFile @project_id, @file_id, @newProject_id, @newFile_id, (err)=>
				err.should.equal error
				done()

		it "should return an error for a non-success statusCode", (done)->
			@request.callsArgWith(1, null, {statusCode: 500})
			@handler.copyFile @project_id, @file_id, @newProject_id, @newFile_id, (err)=>
				err.should.be.an('error')
				err.message.should.equal 'non-ok response from filestore for copyFile: 500'
				done()