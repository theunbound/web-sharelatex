should = require('chai').should()
expect = require("chai").expect
SandboxedModule = require('sandboxed-module')
assert = require('assert')
path = require('path')
sinon = require('sinon')
modulePath = path.join __dirname, "../../../../app/js/Features/PasswordReset/PasswordResetController"
expect = require("chai").expect

describe "PasswordResetController", ->

	beforeEach ->

		@settings = {}
		@PasswordResetHandler =
			generateAndEmailResetToken:sinon.stub()
			setNewUserPassword:sinon.stub()
		@RateLimiter =
			addCount: sinon.stub()
		@UserSessionsManager =
			revokeAllUserSessions: sinon.stub().callsArgWith(2, null)
		@AuthenticationManager =
			validatePassword: sinon.stub()
		@UserUpdater =
			removeReconfirmFlag: sinon.stub().callsArgWith(1, null)
		@PasswordResetController = SandboxedModule.require modulePath, requires:
			"settings-sharelatex":@settings
			"./PasswordResetHandler":@PasswordResetHandler
			"logger-sharelatex": log:->
			"../../infrastructure/RateLimiter":@RateLimiter
			"../Authentication/AuthenticationController": @AuthenticationController = {}
			"../Authentication/AuthenticationManager": @AuthenticationManager
			"../User/UserGetter": @UserGetter = {}
			"../User/UserSessionsManager": @UserSessionsManager
			"../User/UserUpdater": 	@UserUpdater

		@email = "bob@bob.com "
		@user_id = 'mock-user-id'
		@token = "my security token that was emailed to me"
		@password = "my new password"
		@req =
			body:
				email:@email
				passwordResetToken:@token
				password:@password
			i18n:
				translate:->
			session: {}
			query: {}

		@res = {}


	describe "requestReset", ->

		it "should error if the rate limit is hit", (done)->
			@PasswordResetHandler.generateAndEmailResetToken.callsArgWith(1, null, 'primary')
			@RateLimiter.addCount.callsArgWith(1, null, false)
			@res.send = (code)=>
				code.should.equal 429
				@PasswordResetHandler.generateAndEmailResetToken.calledWith(@email.trim()).should.equal false
				done()
			@PasswordResetController.requestReset @req, @res


		it "should tell the handler to process that email", (done)->
			@RateLimiter.addCount.callsArgWith(1, null, true)
			@PasswordResetHandler.generateAndEmailResetToken.callsArgWith(1, null, 'primary')
			@res.send = (code)=>
				code.should.equal 200
				@PasswordResetHandler.generateAndEmailResetToken.calledWith(@email.trim()).should.equal true
				done()
			@PasswordResetController.requestReset @req, @res

		it "should send a 500 if there is an error", (done)->
			@RateLimiter.addCount.callsArgWith(1, null, true)
			@PasswordResetHandler.generateAndEmailResetToken.callsArgWith(1, "error")
			@res.send = (code)=>
				code.should.equal 500
				done()
			@PasswordResetController.requestReset @req, @res

		it "should send a 404 if the email doesn't exist", (done)->
			@RateLimiter.addCount.callsArgWith(1, null, true)
			@PasswordResetHandler.generateAndEmailResetToken.callsArgWith(1, null, null)
			@res.send = (code)=>
				code.should.equal 404
				done()
			@PasswordResetController.requestReset @req, @res

		it "should send a 404 if the email is registered as a secondard email", (done)->
			@RateLimiter.addCount.callsArgWith(1, null, true)
			@PasswordResetHandler.generateAndEmailResetToken.callsArgWith(1, null, 'secondary')
			@res.send = (code)=>
				code.should.equal 404
				done()
			@PasswordResetController.requestReset @req, @res

		it "should lowercase the email address", (done)->
			@email = "UPerCaseEMAIL@example.Com"
			@req.body.email = @email
			@RateLimiter.addCount.callsArgWith(1, null, true)
			@PasswordResetHandler.generateAndEmailResetToken.callsArgWith(1, null, 'primary')
			@res.send = (code)=>
				code.should.equal 200
				@PasswordResetHandler.generateAndEmailResetToken.calledWith(@email.toLowerCase()).should.equal true
				done()
			@PasswordResetController.requestReset @req, @res

	describe "setNewUserPassword", ->

		beforeEach ->
			@req.session.resetToken = @token

		it "should tell the user handler to reset the password", (done)->
			@PasswordResetHandler.setNewUserPassword.callsArgWith(2, null, true, @user_id)
			@res.sendStatus = (code)=>
				code.should.equal 200
				@PasswordResetHandler.setNewUserPassword.calledWith(@token, @password).should.equal true
				done()
			@PasswordResetController.setNewUserPassword @req, @res

		it "should send 404 if the token didn't work", (done)->
			@PasswordResetHandler.setNewUserPassword.callsArgWith(2, null, false, @user_id)
			@res.sendStatus = (code)=>
				code.should.equal 404
				done()
			@PasswordResetController.setNewUserPassword @req, @res

		it "should return 400 (Bad Request) if there is no password", (done)->
			@req.body.password = ""
			@PasswordResetHandler.setNewUserPassword.callsArgWith(2)
			@res.sendStatus = (code)=>
				code.should.equal 400
				@PasswordResetHandler.setNewUserPassword.called.should.equal false
				done()
			@PasswordResetController.setNewUserPassword @req, @res

		it "should return 400 (Bad Request) if there is no passwordResetToken", (done)->
			@req.body.passwordResetToken = ""
			@PasswordResetHandler.setNewUserPassword.callsArgWith(2)
			@res.sendStatus = (code)=>
				code.should.equal 400
				@PasswordResetHandler.setNewUserPassword.called.should.equal false
				done()
			@PasswordResetController.setNewUserPassword @req, @res

		it "should return 400 (Bad Request) if the password is invalid", (done)->
			@req.body.password = "correct horse battery staple"
			@AuthenticationManager.validatePassword = sinon.stub().returns { message: 'password contains invalid characters' }
			@PasswordResetHandler.setNewUserPassword.callsArgWith(2)
			@res.sendStatus = (code)=>
				code.should.equal 400
				@PasswordResetHandler.setNewUserPassword.called.should.equal false
				done()
			@PasswordResetController.setNewUserPassword @req, @res

		it "should clear the session.resetToken", (done) ->
			@PasswordResetHandler.setNewUserPassword.callsArgWith(2, null, true, @user_id)
			@res.sendStatus = (code)=>
				code.should.equal 200
				@req.session.should.not.have.property 'resetToken'
				done()
			@PasswordResetController.setNewUserPassword @req, @res

		it 'should clear sessions', (done) ->
			@PasswordResetHandler.setNewUserPassword.callsArgWith(2, null, true, @user_id)
			@res.sendStatus = (code)=>
				@UserSessionsManager.revokeAllUserSessions.callCount.should.equal 1
				done()
			@PasswordResetController.setNewUserPassword @req, @res

		it 'should call removeReconfirmFlag', (done) ->
			@PasswordResetHandler.setNewUserPassword.callsArgWith(2, null, true, @user_id)
			@res.sendStatus = (code)=>
				@UserUpdater.removeReconfirmFlag.callCount.should.equal 1
				done()
			@PasswordResetController.setNewUserPassword @req, @res

		describe 'when login_after is set', ->

			beforeEach ->
				@UserGetter.getUser = sinon.stub().callsArgWith(2, null, { email: "joe@example.com" })
				@PasswordResetHandler.setNewUserPassword.callsArgWith(2, null, true, @user_id = "user-id-123")
				@req.body.login_after = "true"
				@res.json = sinon.stub()
				@AuthenticationController.afterLoginSessionSetup = sinon.stub().callsArgWith(2, null)
				@AuthenticationController._getRedirectFromSession = sinon.stub().returns('/some/path')

			it "should login user if login_after is set", (done) ->
				@PasswordResetController.setNewUserPassword @req, @res
				@AuthenticationController.afterLoginSessionSetup.callCount.should.equal 1
				@AuthenticationController.afterLoginSessionSetup.calledWith(
					@req,
					{email: 'joe@example.com'}
				).should.equal true
				@AuthenticationController._getRedirectFromSession.callCount.should.equal 1
				@res.json.callCount.should.equal 1
				@res.json.calledWith({redir: '/some/path'}).should.equal true
				done()

	describe "renderSetPasswordForm", ->

		describe "with token in query-string", ->
			beforeEach ->
				@req.query.passwordResetToken = @token

			it "should set session.resetToken and redirect", (done) ->
				@req.session.should.not.have.property 'resetToken'
				@res.redirect = (path) =>
					path.should.equal '/user/password/set'
					@req.session.resetToken.should.equal @token
					done()
				@PasswordResetController.renderSetPasswordForm(@req, @res)

		describe "without a token in query-string", ->

			describe "with token in session", ->
				beforeEach ->
					@req.session.resetToken = @token

				it "should render the page, passing the reset token", (done) ->
					@res.render = (template_path, options) =>
						options.passwordResetToken.should.equal @req.session.resetToken
						done()
					@PasswordResetController.renderSetPasswordForm(@req, @res)

			describe "without a token in session", ->

				it "should redirect to the reset request page", (done) ->
					@res.redirect = (path) =>
						path.should.equal "/user/password/reset"
						@req.session.should.not.have.property 'resetToken'
						done()
					@PasswordResetController.renderSetPasswordForm(@req, @res)
