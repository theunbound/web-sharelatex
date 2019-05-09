SandboxedModule = require('sandboxed-module')
should = require('chai').should()
sinon = require 'sinon'
querystring = require 'querystring'
modulePath = "../../../../app/js/Features/Subscription/SubscriptionHandler"

mockRecurlySubscriptions =
	"subscription-123-active":
		uuid: "subscription-123-active"
		plan:
			name: "Gold"
			plan_code: "gold"
		current_period_ends_at: new Date()
		state: "active"
		unit_amount_in_cents: 999
		account:
			account_code: "user-123"
			
describe "SubscriptionHandler", ->

	beforeEach ->
		@Settings = 
			plans : [{
				planCode: "collaborator"
				name: "Collaborator"
				features:
					collaborators: -1
					versioning: true
			}]
			defaultPlanCode :
				collaborators: 0
				versioning: false
		@activeRecurlySubscription = mockRecurlySubscriptions["subscription-123-active"]
		@User = {}
		@user =
			_id: @user_id = "user_id_here_"
		@subscription = 
			recurlySubscription_id: @activeRecurlySubscription.uuid
		@RecurlyWrapper = 
			getSubscription: sinon.stub().callsArgWith(2, null, @activeRecurlySubscription)
			updateSubscription: sinon.stub().callsArgWith(2, null, @activeRecurlySubscription)
			cancelSubscription: sinon.stub().callsArgWith(1)
			reactivateSubscription: sinon.stub().callsArgWith(1)
			redeemCoupon:sinon.stub().callsArgWith(2)
			createSubscription: sinon.stub().callsArgWith(3, null, @activeRecurlySubscription)

		@DropboxHandler =
			unlinkAccount:sinon.stub().callsArgWith(1)

		@SubscriptionUpdater = 
			syncSubscription: sinon.stub().callsArgWith(2)
			startFreeTrial: sinon.stub().callsArgWith(1)

		@LimitationsManager =
			userHasV2Subscription: sinon.stub()

		@EmailHandler =
			sendEmail:sinon.stub()

		@AnalyticsManager = 
			recordEvent:sinon.stub()
			
		@SubscriptionHandler = SandboxedModule.require modulePath, requires:
			"./RecurlyWrapper": @RecurlyWrapper
			"settings-sharelatex": @Settings
			'../../models/User': User:@User
			'./SubscriptionUpdater': @SubscriptionUpdater
			"logger-sharelatex":{log:->}
			'./LimitationsManager':@LimitationsManager
			"../Email/EmailHandler":@EmailHandler
			"../Dropbox/DropboxHandler":@DropboxHandler
			"../../infrastructure/Events": @Events = {emit: sinon.stub()}
			"../Analytics/AnalyticsManager": @AnalyticsManager

		@SubscriptionHandler.syncSubscriptionToUser = sinon.stub().callsArgWith(2)


	describe "createSubscription", ->
		beforeEach ->
			@callback = sinon.stub()
			@subscriptionDetails = 
				cvv:"123"
				number:"12345"
			@recurly_token_id = "45555666"
			@SubscriptionHandler.validateNoSubscriptionInRecurly = sinon.stub().yields(null, true)

		describe "successfully", ->
			beforeEach ->
				@SubscriptionHandler.createSubscription(@user, @subscriptionDetails, @recurly_token_id, @callback)

			it "should create the subscription with the wrapper", ->
				@RecurlyWrapper.createSubscription.calledWith(@user, @subscriptionDetails, @recurly_token_id).should.equal true

			it "should sync the subscription to the user", ->
				@SubscriptionUpdater.syncSubscription.calledOnce.should.equal true
				@SubscriptionUpdater.syncSubscription.args[0][0].should.deep.equal @activeRecurlySubscription
				@SubscriptionUpdater.syncSubscription.args[0][1].should.deep.equal @user._id

		describe "when there is already a subscription in Recurly", ->
			beforeEach ->
				@SubscriptionHandler.validateNoSubscriptionInRecurly = sinon.stub().yields(null, false)
				@SubscriptionHandler.createSubscription(@user, @subscriptionDetails, @recurly_token_id, @callback)
			
			it "should return an error", ->
				@callback.calledWith(new Error("user already has subscription in recurly"))

	describe "updateSubscription", ->
		describe "with a user with a subscription", ->
			describe "with a valid plan code", ->
				beforeEach (done) ->
					@plan_code = "collaborator"
					@LimitationsManager.userHasV2Subscription.callsArgWith(1, null, true, @subscription)
					@SubscriptionHandler.updateSubscription(@user, @plan_code, null, done)

				it "should update the subscription", ->
					@RecurlyWrapper.updateSubscription.calledWith(@subscription.recurlySubscription_id).should.equal true
					updateOptions = @RecurlyWrapper.updateSubscription.args[0][1]
					updateOptions.plan_code.should.equal @plan_code
			
				it "should update immediately", ->
					updateOptions = @RecurlyWrapper.updateSubscription.args[0][1]
					updateOptions.timeframe.should.equal "now"

				it "should sync the new subscription to the user", ->
					@SubscriptionUpdater.syncSubscription.calledOnce.should.equal true
					@SubscriptionUpdater.syncSubscription.args[0][0].should.deep.equal @activeRecurlySubscription
					@SubscriptionUpdater.syncSubscription.args[0][1].should.deep.equal @user._id

		describe "with a user without a subscription", ->
			beforeEach (done) ->
				@LimitationsManager.userHasV2Subscription.callsArgWith(1, null, false)
				@SubscriptionHandler.updateSubscription(@user, @plan_code, null, done)

			it "should redirect to the subscription dashboard", ->
				@RecurlyWrapper.updateSubscription.called.should.equal false
				@SubscriptionHandler.syncSubscriptionToUser.called.should.equal false

		describe "with a coupon code", ->
			beforeEach (done) ->
				@plan_code = "collaborator"
				@coupon_code = "1231312"
				@LimitationsManager.userHasV2Subscription.callsArgWith(1, null, true, @subscription)
				@SubscriptionHandler.updateSubscription(@user, @plan_code, @coupon_code, done)

			it "should get the users account", ->
				@RecurlyWrapper.getSubscription.calledWith(@activeRecurlySubscription.uuid).should.equal true

			it "should redeme the coupon", (done)->
				@RecurlyWrapper.redeemCoupon.calledWith(@activeRecurlySubscription.account.account_code, @coupon_code).should.equal true
				done()

			it "should update the subscription", ->
				@RecurlyWrapper.updateSubscription.calledWith(@subscription.recurlySubscription_id).should.equal true
				updateOptions = @RecurlyWrapper.updateSubscription.args[0][1]
				updateOptions.plan_code.should.equal @plan_code

	describe "cancelSubscription", ->
		describe "with a user without a subscription", ->
			beforeEach (done) ->
				@LimitationsManager.userHasV2Subscription.callsArgWith(1, null, false, @subscription)
				@SubscriptionHandler.cancelSubscription @user, done


			it "should redirect to the subscription dashboard", ->
				@RecurlyWrapper.cancelSubscription.called.should.equal false

		describe "with a user with a subscription", ->
			beforeEach (done)  ->
				@LimitationsManager.userHasV2Subscription.callsArgWith(1, null, true, @subscription)
				@SubscriptionHandler.cancelSubscription @user, done

			it "should cancel the subscription", ->
				@RecurlyWrapper.cancelSubscription.called.should.equal true
				@RecurlyWrapper.cancelSubscription.calledWith(@subscription.recurlySubscription_id).should.equal true

			it "should trigger the cancel subscription event", ->
				@Events.emit.calledWith("cancelSubscription", @user._id).should.equal true

	describe "reactiveRecurlySubscription", ->
		describe "with a user without a subscription", ->
			beforeEach (done) ->
				@LimitationsManager.userHasV2Subscription.callsArgWith(1, null, false, @subscription)
				@SubscriptionHandler.reactivateSubscription @user, done

			it "should redirect to the subscription dashboard", ->
				@RecurlyWrapper.reactivateSubscription.called.should.equal false

			it "should not send a notification email", ->
				sinon.assert.notCalled(@EmailHandler.sendEmail)

		describe "with a user with a subscription", ->
			beforeEach (done)  ->
				@LimitationsManager.userHasV2Subscription.callsArgWith(1, null, true, @subscription)
				@SubscriptionHandler.reactivateSubscription @user, done

			it "should reactivate the subscription", ->
				@RecurlyWrapper.reactivateSubscription.called.should.equal true
				@RecurlyWrapper.reactivateSubscription.calledWith(@subscription.recurlySubscription_id).should.equal true

			it "should send a notification email", ->
				sinon.assert.calledWith(@EmailHandler.sendEmail, 'reactivatedSubscription')

	describe "recurlyCallback", ->
		describe "with an actionable request", ->
			beforeEach (done) ->
				@user.id = @activeRecurlySubscription.account.account_code

				@User.findById = (userId, callback) =>
					userId.should.equal @user.id
					callback null, @user
				@SubscriptionHandler.recurlyCallback(@activeRecurlySubscription, done)

			it "should request the affected subscription from the API", ->
				@RecurlyWrapper.getSubscription.calledWith(@activeRecurlySubscription.uuid).should.equal true

			it "should request the account details of the subscription", ->
				options = @RecurlyWrapper.getSubscription.args[0][1]
				options.includeAccount.should.equal true

			it "should sync the subscription to the user", ->
				@SubscriptionUpdater.syncSubscription.calledOnce.should.equal true
				@SubscriptionUpdater.syncSubscription.args[0][0].should.deep.equal @activeRecurlySubscription
				@SubscriptionUpdater.syncSubscription.args[0][1].should.deep.equal @user._id

	describe "validateNoSubscriptionInRecurly", ->
		beforeEach ->
			@subscriptions = []
			@RecurlyWrapper.listAccountActiveSubscriptions = sinon.stub().yields(null, @subscriptions)
			@SubscriptionUpdater.syncSubscription = sinon.stub().yields()
			@callback = sinon.stub()

		describe "with no subscription in recurly", ->
			beforeEach ->
				@subscriptions.push @subscription = { "mock": "subscription" }
				@SubscriptionHandler.validateNoSubscriptionInRecurly @user_id, @callback

			it "should call RecurlyWrapper.listAccountActiveSubscriptions with the user id", ->
				@RecurlyWrapper.listAccountActiveSubscriptions
					.calledWith(@user_id)
					.should.equal true

			it "should sync the subscription", ->
				@SubscriptionUpdater.syncSubscription
					.calledWith(@subscription, @user_id)
					.should.equal true

			it "should call the callback with valid == false", ->
				@callback.calledWith(null, false).should.equal true

		describe "with a subscription in recurly", ->
			beforeEach ->
				@SubscriptionHandler.validateNoSubscriptionInRecurly @user_id, @callback

			it "should not sync the subscription", ->
				@SubscriptionUpdater.syncSubscription
					.called
					.should.equal false

			it "should call the callback with valid == true", ->
				@callback.calledWith(null, true).should.equal true
