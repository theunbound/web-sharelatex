async = require("async")
RecurlyWrapper = require("./RecurlyWrapper")
Settings = require "settings-sharelatex"
User = require('../../models/User').User
logger = require('logger-sharelatex')
SubscriptionUpdater = require("./SubscriptionUpdater")
LimitationsManager = require('./LimitationsManager')
EmailHandler = require("../Email/EmailHandler")
Events = require "../../infrastructure/Events"
Analytics = require("../Analytics/AnalyticsManager")


module.exports =
	validateNoSubscriptionInRecurly: (user_id, callback = (error, valid) ->) ->
		RecurlyWrapper.listAccountActiveSubscriptions user_id, (error, subscriptions = []) ->
			return callback(error) if error?
			if subscriptions.length > 0
				SubscriptionUpdater.syncSubscription subscriptions[0], user_id, (error) ->
					return callback(error) if error?
					return callback(null, false)
			else
				return callback(null, true)

	createSubscription: (user, subscriptionDetails, recurly_token_id, callback)->
		self = @
		clientTokenId = ""
		@validateNoSubscriptionInRecurly user._id, (error, valid) ->
			return callback(error) if error?
			if !valid
				return callback(new Error("user already has subscription in recurly"))
			RecurlyWrapper.createSubscription user, subscriptionDetails, recurly_token_id, (error, recurlySubscription)->
				return callback(error) if error?
				SubscriptionUpdater.syncSubscription recurlySubscription, user._id, (error) ->
					return callback(error) if error?
					callback()

	updateSubscription: (user, plan_code, coupon_code, callback)->
		logger.log user:user, plan_code:plan_code, coupon_code:coupon_code, "updating subscription"
		LimitationsManager.userHasV2Subscription user, (err, hasSubscription, subscription)->
			if !hasSubscription
				return callback()
			else
				async.series [
					(cb)->
						return cb() if !coupon_code?
						logger.log user_id:user._id, plan_code:plan_code, coupon_code:coupon_code, "updating subscription with coupon code applied first"
						RecurlyWrapper.getSubscription subscription.recurlySubscription_id, includeAccount: true, (err, usersSubscription)->
							return callback(err) if err?
							account_code = usersSubscription.account.account_code
							RecurlyWrapper.redeemCoupon account_code, coupon_code, cb
					(cb)->
						RecurlyWrapper.updateSubscription subscription.recurlySubscription_id, {plan_code: plan_code, timeframe: "now"}, (error, recurlySubscription) ->
							return callback(error) if error?
							SubscriptionUpdater.syncSubscription recurlySubscription, user._id, cb
				], callback
		

	cancelSubscription: (user, callback) ->
		LimitationsManager.userHasV2Subscription user, (err, hasSubscription, subscription)->
			if hasSubscription
				RecurlyWrapper.cancelSubscription subscription.recurlySubscription_id, (error) ->
					return callback(error) if error?
					emailOpts =
						to: user.email
						first_name: user.first_name
					ONE_HOUR_IN_MS = 1000 * 60 * 60
					setTimeout (-> EmailHandler.sendEmail "canceledSubscription", emailOpts
					), ONE_HOUR_IN_MS
					Events.emit "cancelSubscription", user._id
					Analytics.recordEvent user._id, "subscription-canceled"
					callback()
			else
				callback()

	reactivateSubscription: (user, callback) ->
		LimitationsManager.userHasV2Subscription user, (err, hasSubscription, subscription)->
			if hasSubscription
				RecurlyWrapper.reactivateSubscription subscription.recurlySubscription_id, (error) ->
					return callback(error) if error?
					EmailHandler.sendEmail "reactivatedSubscription", to: user.email
					Analytics.recordEvent user._id, "subscription-reactivated"
					callback()
			else
				callback()

	recurlyCallback: (recurlySubscription, callback) ->
		RecurlyWrapper.getSubscription recurlySubscription.uuid, includeAccount: true, (error, recurlySubscription) ->
			return callback(error) if error?
			User.findById recurlySubscription.account.account_code, (error, user) ->
				return callback(error) if error?
				if !user?
					return callback("no user found")
				SubscriptionUpdater.syncSubscription recurlySubscription, user?._id, callback

	extendTrial: (subscription, daysToExend, callback)->
		RecurlyWrapper.extendTrial subscription.recurlySubscription_id, daysToExend, callback
