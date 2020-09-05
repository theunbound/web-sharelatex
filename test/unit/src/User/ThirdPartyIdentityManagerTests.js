const sinon = require('sinon')
const chai = require('chai')
const { expect } = chai
const SandboxedModule = require('sandboxed-module')
const modulePath =
  '../../../../app/src/Features/User/ThirdPartyIdentityManager.js'

describe('ThirdPartyIdentityManager', function() {
  beforeEach(function() {
    this.userId = 'a1b2c3'
    this.user = {
      _id: this.userId,
      email: 'example@overleaf.com'
    }
    this.externalUserId = 'id789'
    this.externalData = {}
    this.ThirdPartyIdentityManager = SandboxedModule.require(modulePath, {
      globals: {
        console: console
      },
      requires: {
        '../../../../app/src/Features/Email/EmailHandler': (this.EmailHandler = {
          sendEmail: sinon.stub().yields()
        }),
        Errors: (this.Errors = {
          ThirdPartyIdentityExistsError: sinon.stub(),
          ThirdPartyUserNotFoundError: sinon.stub()
        }),
        '../../../../app/src/models/User': {
          User: (this.User = {
            findOneAndUpdate: sinon.stub().yields(undefined, this.user),
            findOne: sinon.stub()
          })
        },
        'settings-sharelatex': {
          oauthProviders: {
            google: {
              name: 'Google'
            },
            orcid: {
              name: 'Orcid'
            }
          }
        }
      }
    })
  })
  describe('link', function() {
    it('should send email alert', async function() {
      await this.ThirdPartyIdentityManager.promises.link(
        this.userId,
        'google',
        this.externalUserId,
        this.externalData
      )
      const emailCall = this.EmailHandler.sendEmail.getCall(0)
      expect(emailCall.args[0]).to.equal('securityAlert')
      expect(emailCall.args[1].actionDescribed).to.contain(
        'a Google account was linked'
      )
    })
  })
  describe('unlink', function() {
    it('should send email alert', async function() {
      await this.ThirdPartyIdentityManager.promises.unlink(this.userId, 'orcid')
      const emailCall = this.EmailHandler.sendEmail.getCall(0)
      expect(emailCall.args[0]).to.equal('securityAlert')
      expect(emailCall.args[1].actionDescribed).to.contain(
        'an Orcid account is no longer linked'
      )
    })
  })
})
