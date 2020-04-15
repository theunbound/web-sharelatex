const { ObjectId } = require('../../../../app/src/infrastructure/mongojs')
const Subscription = require('./Subscription')
const MockRecurlyApi = require('./MockRecurlyApi')
const RecurlyWrapper = require('../../../../app/src/Features/Subscription/RecurlyWrapper')

class RecurlySubscription {
  constructor(options = {}) {
    options.recurlySubscription_id = ObjectId().toString()
    this.subscription = new Subscription(options)

    this.uuid = options.recurlySubscription_id
    this.state = options.state || 'active'
    this.tax_in_cents = 100
    this.tax_rate = 0.2
    this.unit_amount_in_cents = 500
    this.currency = 'GBP'
    this.current_period_ends_at = new Date(2018, 4, 5)
    this.trial_ends_at = new Date(2018, 6, 7)
    this.account = {
      id: this.subscription.admin_id.toString(),
      email: options.account && options.account.email,
      hosted_login_token: options.account && options.account.hosted_login_token
    }
  }

  ensureExists(callback) {
    this.subscription.ensureExists(error => {
      if (error) {
        return callback(error)
      }
      MockRecurlyApi.addMockSubscription(this)
      callback()
    })
  }

  buildCallbackXml() {
    return RecurlyWrapper._buildXml('expired_subscription_notification', {
      subscription: {
        uuid: this.uuid
      }
    })
  }
}

module.exports = RecurlySubscription
