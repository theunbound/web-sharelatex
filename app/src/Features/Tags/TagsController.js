/* eslint-disable
    camelcase,
    max-len,
*/
// TODO: This file was created by bulk-decaffeinate.
// Fix any style issues and re-enable lint.
/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const TagsHandler = require('./TagsHandler')
const AuthenticationController = require('../Authentication/AuthenticationController')

module.exports = {
  getAllTags(req, res, next) {
    const user_id = AuthenticationController.getLoggedInUserId(req)
    return TagsHandler.getAllTags(user_id, function(error, allTags) {
      if (error != null) {
        return next(error)
      }
      return res.json(allTags)
    })
  },

  createTag(req, res, next) {
    const user_id = AuthenticationController.getLoggedInUserId(req)
    const { name } = req.body
    return TagsHandler.createTag(user_id, name, function(error, tag) {
      if (error != null) {
        return next(error)
      }
      return res.json(tag)
    })
  },

  addProjectToTag(req, res, next) {
    const user_id = AuthenticationController.getLoggedInUserId(req)
    const { tag_id, project_id } = req.params
    return TagsHandler.addProjectToTag(user_id, tag_id, project_id, function(
      error
    ) {
      if (error != null) {
        return next(error)
      }
      return res.status(204).end()
    })
  },

  removeProjectFromTag(req, res, next) {
    const user_id = AuthenticationController.getLoggedInUserId(req)
    const { tag_id, project_id } = req.params
    return TagsHandler.removeProjectFromTag(
      user_id,
      tag_id,
      project_id,
      function(error) {
        if (error != null) {
          return next(error)
        }
        return res.status(204).end()
      }
    )
  },

  deleteTag(req, res, next) {
    const user_id = AuthenticationController.getLoggedInUserId(req)
    const { tag_id } = req.params
    return TagsHandler.deleteTag(user_id, tag_id, function(error) {
      if (error != null) {
        return next(error)
      }
      return res.status(204).end()
    })
  },

  renameTag(req, res, next) {
    const user_id = AuthenticationController.getLoggedInUserId(req)
    const { tag_id } = req.params
    const name = req.body != null ? req.body.name : undefined
    if (name == null) {
      return res.status(400).end()
    } else {
      return TagsHandler.renameTag(user_id, tag_id, name, function(error) {
        if (error != null) {
          return next(error)
        }
        return res.status(204).end()
      })
    }
  }
}
