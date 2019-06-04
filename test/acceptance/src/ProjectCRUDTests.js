/* eslint-disable
    handle-callback-err,
    max-len,
    no-unused-vars,
*/
// TODO: This file was created by bulk-decaffeinate.
// Fix any style issues and re-enable lint.
/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const { expect } = require('chai')
const async = require('async')
const User = require('./helpers/User')

describe('Project CRUD', function() {
  before(function(done) {
    this.user = new User()
    return this.user.login(done)
  })

  describe("when project doesn't exist", () =>
    it('should return 404', function(done) {
      return this.user.request.get(
        '/project/aaaaaaaaaaaaaaaaaaaaaaaa',
        function(err, res, body) {
          expect(res.statusCode).to.equal(404)
          return done()
        }
      )
    }))

  return describe('when project has malformed id', () =>
    it('should return 404', function(done) {
      return this.user.request.get('/project/blah', function(err, res, body) {
        expect(res.statusCode).to.equal(404)
        return done()
      })
    }))
})
