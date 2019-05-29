sinon = require('sinon')
chai = require('chai')
should = chai.should()
expect = chai.expect
modulePath = "../../../../app/js/Features/User/UserDeleter.js"
SandboxedModule = require('sandboxed-module')
Errors = require('../../../../app/js/Features/Errors/Errors')

describe "UserDeleter", ->

	beforeEach ->
		@user = 
			_id: "12390i"
			email: "bob@bob.com"
			remove: sinon.stub().callsArgWith(0)

		@User =
			findById : sinon.stub().callsArgWith(1, null, @user)

		@NewsletterManager = 
			unsubscribe: sinon.stub().callsArgWith(1)

		@ProjectDeleter =
			deleteUsersProjects: sinon.stub().callsArgWith(1)

		@SubscriptionHandler = 
			cancelSubscription: sinon.stub().callsArgWith(1)

		@SubscriptionUpdater =
			removeUserFromAllGroups: sinon.stub().callsArgWith(1)

		@SubscriptionLocator =
			getUsersSubscription: sinon.stub().yields(null, null)

		@UserMembershipsHandler =
			removeUserFromAllEntities: sinon.stub().callsArgWith(1)

		@deleteAffiliations = sinon.stub().callsArgWith(1)

		@mongojs =
			db:
				deletedUsers:
					insert: sinon.stub().callsArg(1)
				usersDeletedByMigration:
					insert: sinon.stub().callsArg(1)

		@UserDeleter = SandboxedModule.require modulePath, requires:
			"../../models/User": User: @User
			"../Newsletter/NewsletterManager":  @NewsletterManager
			"../Subscription/SubscriptionHandler": @SubscriptionHandler
			"../Subscription/SubscriptionUpdater": @SubscriptionUpdater
			"../Subscription/SubscriptionLocator": @SubscriptionLocator
			"../UserMembership/UserMembershipsHandler": @UserMembershipsHandler
			"../Project/ProjectDeleter": @ProjectDeleter
			"../Institutions/InstitutionsAPI":
				deleteAffiliations: @deleteAffiliations
			"../../infrastructure/mongojs": @mongojs
			"logger-sharelatex": @logger = { log: sinon.stub(), err: sinon.stub() }
			"../Errors/Errors": Errors

	describe "softDeleteUserForMigration", ->
		beforeEach ->
			@UserDeleter._ensureCanDeleteUser = sinon.stub().yields(null)

		it "should delete the user in mongo", (done)->
			@UserDeleter.softDeleteUserForMigration @user._id, (err)=>
				@User.findById.calledWith(@user._id).should.equal true
				@user.remove.called.should.equal true
				done()

		it "should add the user to the deletedUsers collection", (done)->
			@UserDeleter.softDeleteUserForMigration @user._id, (err)=>
				sinon.assert.calledWith(@mongojs.db.usersDeletedByMigration.insert, @user)
				done()

		it "should set the deletedAt field on the user", (done)->
			@UserDeleter.softDeleteUserForMigration @user._id, (err)=>
				@user.deletedAt.should.exist
				done()

		it "should unsubscribe the user from the news letter", (done)->
			@UserDeleter.softDeleteUserForMigration @user._id, (err)=>
				@NewsletterManager.unsubscribe.calledWith(@user).should.equal true
				done()

		it "should unsubscribe the user", (done)->
			@UserDeleter.softDeleteUserForMigration @user._id, (err)=>
				@SubscriptionHandler.cancelSubscription.calledWith(@user).should.equal true
				done()

		it "should delete user affiliations", (done)->
			@UserDeleter.softDeleteUserForMigration @user._id, (err)=>
				@deleteAffiliations.calledWith(@user._id).should.equal true
				done()

		it "should delete all the projects of a user", (done)->
			@UserDeleter.softDeleteUserForMigration @user._id, (err)=>
				@ProjectDeleter.deleteUsersProjects.calledWith(@user._id).should.equal true
				done()

		it "should remove user memberships", (done)->
			@UserDeleter.softDeleteUserForMigration @user._id, (err)=>
				@UserMembershipsHandler.removeUserFromAllEntities.calledWith(@user._id).should.equal true
				done()

		it "ensures user can be deleted first", (done)->
			@UserDeleter._ensureCanDeleteUser.yields(
				new Errors.SubscriptionAdminDeletionError()
			)
			@UserDeleter.softDeleteUserForMigration @user._id, (error) =>
				sinon.assert.calledWith(@UserDeleter._ensureCanDeleteUser, @user)
				sinon.assert.notCalled(@user.remove)
				expect(error).to.be.instanceof Errors.SubscriptionAdminDeletionError
				done()

	describe "deleteUser", ->
		beforeEach ->
			@UserDeleter._ensureCanDeleteUser = sinon.stub().yields(null)

		it "should delete the user in mongo", (done)->
			@UserDeleter.deleteUser @user._id, (err)=>
				@User.findById.calledWith(@user._id).should.equal true
				@user.remove.called.should.equal true
				done()

		it "should unsubscribe the user from the news letter", (done)->
			@UserDeleter.deleteUser @user._id, (err)=>
				@NewsletterManager.unsubscribe.calledWith(@user).should.equal true
				done()

		it "should delete all the projects of a user", (done)->
			@UserDeleter.deleteUser @user._id, (err)=>
				@ProjectDeleter.deleteUsersProjects.calledWith(@user._id).should.equal true
				done()

		it "should unsubscribe the user", (done)->
			@UserDeleter.deleteUser @user._id, (err)=>
				@SubscriptionHandler.cancelSubscription.calledWith(@user).should.equal true
				done()

		it "should delete user affiliations", (done)->
			@UserDeleter.deleteUser @user._id, (err)=>
				@deleteAffiliations.calledWith(@user._id).should.equal true
				done()

		it "should remove user from group subscriptions", (done)->
			@UserDeleter.deleteUser @user._id, (err)=>
				@SubscriptionUpdater.removeUserFromAllGroups.calledWith(@user._id).should.equal true
				done()

		it "should remove user memberships", (done)->
			@UserDeleter.deleteUser @user._id, (err)=>
				@UserMembershipsHandler.removeUserFromAllEntities.calledWith(@user._id).should.equal true
				done()

		it "ensures user can be deleted first", (done)->
			@UserDeleter._ensureCanDeleteUser.yields(
				new Errors.SubscriptionAdminDeletionError()
			)
			@UserDeleter.deleteUser @user._id, (error) =>
				sinon.assert.calledWith(@UserDeleter._ensureCanDeleteUser, @user)
				sinon.assert.notCalled(@user.remove)
				expect(error).to.be.instanceof Errors.SubscriptionAdminDeletionError
				done()

		describe "when unsubscribing from mailchimp fails", ->
			beforeEach ->
				@NewsletterManager.unsubscribe = sinon.stub().callsArgWith(1, new Error("something went wrong"))

			it "should not return an error", (done) ->
				@UserDeleter.deleteUser @user._id, (err)=>
					@NewsletterManager.unsubscribe.calledWith(@user).should.equal true
					should.not.exist(err)
					done()

			it "should delete the user", (done) ->
				@UserDeleter.deleteUser @user._id, (err)=>
					@NewsletterManager.unsubscribe.calledWith(@user).should.equal true
					@user.remove.called.should.equal true
					done()

			it "should log an error", (done) ->
				@UserDeleter.deleteUser @user._id, (err)=>
					sinon.assert.called(@logger.err)
					done()

	describe '_ensureCanDeleteUser', ->
		it 'should not return error when user can be deleted', (done) ->
			@SubscriptionLocator.getUsersSubscription.yields(null, null)
			@UserDeleter._ensureCanDeleteUser @user, (error) ->
				expect(error).to.not.exist
				done()

		it 'should return custom error when user is group admin', (done) ->
			@SubscriptionLocator.getUsersSubscription.yields(null, { _id: '123abc' })
			@UserDeleter._ensureCanDeleteUser @user, (error) ->
				expect(error).to.be.instanceof Errors.SubscriptionAdminDeletionError
				done()

		it 'propagate errors', (done) ->
			@SubscriptionLocator.getUsersSubscription.yields(new Error('Some error'))
			@UserDeleter._ensureCanDeleteUser @user, (error) ->
				expect(error).to.be.instanceof Error
				done()
