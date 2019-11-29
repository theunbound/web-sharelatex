/* eslint-disable
    camelcase,
    handle-callback-err,
    max-len,
    no-unused-vars,
    standard/no-callback-literal,
*/
// TODO: This file was created by bulk-decaffeinate.
// Fix any style issues and re-enable lint.
/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const async = require('async')
const RecurlyWrapper = require('./RecurlyWrapper')
const Settings = require('settings-sharelatex')
const { User } = require('../../models/User')
const { promisifyAll } = require('../../util/promises')
const logger = require('logger-sharelatex')
const SubscriptionUpdater = require('./SubscriptionUpdater')
const LimitationsManager = require('./LimitationsManager')
const EmailHandler = require('../Email/EmailHandler')
const Events = require('../../infrastructure/Events')
const Analytics = require('../Analytics/AnalyticsManager')

const SubscriptionHandler = {
  validateNoSubscriptionInRecurly(user_id, callback) {
    if (callback == null) {
      callback = function(error, valid) {}
    }
    return RecurlyWrapper.listAccountActiveSubscriptions(user_id, function(
      error,
      subscriptions
    ) {
      if (subscriptions == null) {
        subscriptions = []
      }
      if (error != null) {
        return callback(error)
      }
      if (subscriptions.length > 0) {
        return SubscriptionUpdater.syncSubscription(
          subscriptions[0],
          user_id,
          function(error) {
            if (error != null) {
              return callback(error)
            }
            return callback(null, false)
          }
        )
      } else {
        return callback(null, true)
      }
    })
  },

  createSubscription(user, subscriptionDetails, recurlyTokenIds, callback) {
    const clientTokenId = ''
    return SubscriptionHandler.validateNoSubscriptionInRecurly(
      user._id,
      function(error, valid) {
        if (error != null) {
          return callback(error)
        }
        if (!valid) {
          return callback(new Error('user already has subscription in recurly'))
        }
        return RecurlyWrapper.createSubscription(
          user,
          subscriptionDetails,
          recurlyTokenIds,
          function(error, recurlySubscription) {
            if (error != null) {
              return callback(error)
            }
            return SubscriptionUpdater.syncSubscription(
              recurlySubscription,
              user._id,
              function(error) {
                if (error != null) {
                  return callback(error)
                }
                return callback()
              }
            )
          }
        )
      }
    )
  },

  updateSubscription(user, plan_code, coupon_code, callback) {
    return LimitationsManager.userHasV2Subscription(user, function(
      err,
      hasSubscription,
      subscription
    ) {
      if (!hasSubscription) {
        return callback()
      } else {
        return async.series(
          [
            function(cb) {
              if (coupon_code == null) {
                return cb()
              }
              return RecurlyWrapper.getSubscription(
                subscription.recurlySubscription_id,
                { includeAccount: true },
                function(err, usersSubscription) {
                  if (err != null) {
                    return callback(err)
                  }
                  const { account_code } = usersSubscription.account
                  return RecurlyWrapper.redeemCoupon(
                    account_code,
                    coupon_code,
                    cb
                  )
                }
              )
            },
            cb =>
              RecurlyWrapper.updateSubscription(
                subscription.recurlySubscription_id,
                { plan_code, timeframe: 'now' },
                function(error, recurlySubscription) {
                  if (error != null) {
                    return callback(error)
                  }
                  return SubscriptionUpdater.syncSubscription(
                    recurlySubscription,
                    user._id,
                    cb
                  )
                }
              )
          ],
          callback
        )
      }
    })
  },

  cancelSubscription(user, callback) {
    return LimitationsManager.userHasV2Subscription(user, function(
      err,
      hasSubscription,
      subscription
    ) {
      if (hasSubscription) {
        return RecurlyWrapper.cancelSubscription(
          subscription.recurlySubscription_id,
          function(error) {
            if (error != null) {
              return callback(error)
            }
            const emailOpts = {
              to: user.email,
              first_name: user.first_name
            }
            const ONE_HOUR_IN_MS = 1000 * 60 * 60
            setTimeout(
              () =>
                EmailHandler.sendEmail(
                  'canceledSubscription',
                  emailOpts,
                  err => {
                    if (err != null) {
                      logger.warn(
                        { err },
                        'failed to send confirmation email for subscription cancellation'
                      )
                    }
                  }
                ),
              ONE_HOUR_IN_MS
            )
            Events.emit('cancelSubscription', user._id)
            Analytics.recordEvent(user._id, 'subscription-canceled')
            return callback()
          }
        )
      } else {
        return callback()
      }
    })
  },

  reactivateSubscription(user, callback) {
    return LimitationsManager.userHasV2Subscription(user, function(
      err,
      hasSubscription,
      subscription
    ) {
      if (hasSubscription) {
        return RecurlyWrapper.reactivateSubscription(
          subscription.recurlySubscription_id,
          function(error) {
            if (error != null) {
              return callback(error)
            }
            EmailHandler.sendEmail(
              'reactivatedSubscription',
              { to: user.email },
              err => {
                if (err != null) {
                  logger.warn(
                    { err },
                    'failed to send reactivation confirmation email'
                  )
                }
              }
            )
            Analytics.recordEvent(user._id, 'subscription-reactivated')
            return callback()
          }
        )
      } else {
        return callback()
      }
    })
  },

  syncSubscription(recurlySubscription, requesterData, callback) {
    return RecurlyWrapper.getSubscription(
      recurlySubscription.uuid,
      { includeAccount: true },
      function(error, recurlySubscription) {
        if (error != null) {
          return callback(error)
        }
        return User.findById(recurlySubscription.account.account_code, function(
          error,
          user
        ) {
          if (error != null) {
            return callback(error)
          }
          if (user == null) {
            return callback(new Error('no user found'))
          }
          return SubscriptionUpdater.syncSubscription(
            recurlySubscription,
            user != null ? user._id : undefined,
            requesterData,
            callback
          )
        })
      }
    )
  },

  // attempt to collect past due invoice for customer. Only do that when a) the
  // customer is using Paypal and b) there is only one past due invoice.
  // This is used because Recurly doesn't always attempt collection of paast due
  // invoices after Paypal billing info were updated.
  attemptPaypalInvoiceCollection(recurlyAccountCode, callback) {
    RecurlyWrapper.getBillingInfo(recurlyAccountCode, (error, billingInfo) => {
      if (error) {
        return callback(error)
      }
      if (!billingInfo.paypal_billing_agreement_id) {
        // this is not a Paypal user
        return callback()
      }
      RecurlyWrapper.getAccountPastDueInvoices(
        recurlyAccountCode,
        (error, pastDueInvoices) => {
          if (error) {
            return callback(error)
          }
          if (pastDueInvoices.length !== 1) {
            // no past due invoices, or more than one. Ignore.
            return callback()
          }
          RecurlyWrapper.attemptInvoiceCollection(
            pastDueInvoices[0].invoice_number,
            callback
          )
        }
      )
    })
  },

  extendTrial(subscription, daysToExend, callback) {
    return RecurlyWrapper.extendTrial(
      subscription.recurlySubscription_id,
      daysToExend,
      callback
    )
  }
}

SubscriptionHandler.promises = promisifyAll(SubscriptionHandler)
module.exports = SubscriptionHandler
