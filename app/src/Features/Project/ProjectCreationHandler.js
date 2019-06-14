/* eslint-disable
    camelcase,
    handle-callback-err,
    max-len,
    no-path-concat,
*/
// TODO: This file was created by bulk-decaffeinate.
// Fix any style issues and re-enable lint.
/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS103: Rewrite code to no longer use __guard__
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
let ProjectCreationHandler
const logger = require('logger-sharelatex')
const async = require('async')
const metrics = require('metrics-sharelatex')
const Settings = require('settings-sharelatex')
const { ObjectId } = require('mongoose').Types
const { Project } = require('../../models/Project')
const { Folder } = require('../../models/Folder')
const ProjectEntityUpdateHandler = require('./ProjectEntityUpdateHandler')
const ProjectDetailsHandler = require('./ProjectDetailsHandler')
const HistoryManager = require('../History/HistoryManager')
const { User } = require('../../models/User')
const fs = require('fs')
const Path = require('path')
const _ = require('underscore')
const AnalyticsManger = require('../Analytics/AnalyticsManager')
const ProjectLocator = require('./ProjectLocator');
const ProjectDuplicator = require('./ProjectDuplicator');

module.exports = ProjectCreationHandler = {
  createBlankProject(owner_id, projectName, attributes, callback) {
    if (callback == null) {
      callback = function(error, project) {}
    }
    metrics.inc('project-creation')
    if (arguments.length === 3) {
      callback = attributes
      attributes = {}
    }

    return ProjectDetailsHandler.validateProjectName(projectName, function(
      error
    ) {
      if (error != null) {
        return callback(error)
      }
      logger.log({ owner_id, projectName }, 'creating blank project')
      if (attributes.overleaf !== undefined && attributes.overleaf != null) {
        return ProjectCreationHandler._createBlankProject(
          owner_id,
          projectName,
          attributes,
          function(error, project) {
            if (error != null) {
              return callback(error)
            }
            AnalyticsManger.recordEvent(owner_id, 'project-imported', {
              projectId: project._id,
              attributes
            })
            return callback(error, project)
          }
        )
      } else {
        return HistoryManager.initializeProject(function(error, history) {
          if (error != null) {
            return callback(error)
          }
          attributes.overleaf = {
            history: { id: history != null ? history.overleaf_id : undefined }
          }
          return ProjectCreationHandler._createBlankProject(
            owner_id,
            projectName,
            attributes,
            function(error, project) {
              if (error != null) {
                return callback(error)
              }
              AnalyticsManger.recordEvent(owner_id, 'project-created', {
                projectId: project._id,
                attributes
              })
              return callback(error, project)
            }
          )
        })
      }
    })
  },

  _createBlankProject(owner_id, projectName, attributes, callback) {
    if (callback == null) {
      callback = function(error, project) {}
    }
    const rootFolder = new Folder({ name: 'rootFolder' })

    attributes.owner_ref = new ObjectId(owner_id)
    attributes.name = projectName
    const project = new Project(attributes)

    Object.assign(project, attributes)

    if (
      __guard__(
        Settings.apis != null ? Settings.apis.project_history : undefined,
        x => x.displayHistoryForNewProjects
      )
    ) {
      project.overleaf.history.display = true
    }
    if (Settings.currentImageName != null) {
      // avoid clobbering any imageName already set in attributes (e.g. importedImageName)
      if (project.imageName == null) {
        project.imageName = Settings.currentImageName
      }
    }
    project.rootFolder[0] = rootFolder
    async.parallel([
      (cb) => {
        User.findById(
          owner_id, 'ace.spellCheckLanguage', function( err, user ) {
            if (user != null) {
              // It's possible the owner_id is a UserStub
              project.spellCheckLanguage = user.ace.spellCheckLanguage;
            }
            cb(null);
          }
        );
      }, (cb) => {
        // Globalize projects
        User.find({ _id: {$ne: owner_id}}, {_id:1}, (err, docs) => {
          if ( err != null ) return cb(err);
          docs.forEach( doc => project.collaberator_refs.push(doc._id) );
          return cb(null);
        });
      }
    ], (error, results) => {
      if (error != null) return callback(error);
      return project.save(function(err) {
        if (err != null) {
          return callback(err)
        }
        return callback(err, project)
      })
    })
  },

  createProjectFromSnippet(owner_id, projectName, docLines, callback) {
    if (callback == null) {
      callback = function(error, project) {}
    }
    return this.createBlankProject(owner_id, projectName, function(
      error,
      project
    ) {
      if (error != null) {
        return callback(error)
      }
      return ProjectCreationHandler._createRootDoc(
        project,
        owner_id,
        docLines,
        null,
        callback
      )
    })
  },

  createBasicProject(owner_id, projectName, template = "mainbasic", callback) {
    if (callback == null) {
      callback = function(error, project) {}
    }
    const self = this
    const mainName = projectName.replace(
        /(?:^[æøå\w]|[A-ZÆØÅ]|\b(\w|æ|ø|å)|\s+)/g, function(match, index) {
        if (+match === 0)
          return "";
        else if (index === 0)
          return match.toLowerCase();
        else
          return match.toUpperCase();
        }
    );
    return this.createBlankProject(owner_id, projectName, function(
      error,
      project
    ) {
      if (error != null) {
        return callback(error)
      }
      return self._buildTemplate(
        template + ".tex",
        owner_id,
        projectName,
        function(error, docLines) {
          if (error != null) {
            return callback(error)
          }
          return ProjectCreationHandler._createRootDoc(
            project,
            owner_id,
            docLines,
            mainName,
            callback
          )
        }
      )
    })
  },

  createExampleProject(owner_id, projectName, callback) {
    if (callback == null) {
      callback = function(error, project) {}
    }
    const self = this
    return this.createBlankProject(owner_id, projectName, function(
      error,
      project
    ) {
      if (error != null) {
        return callback(error)
      }
      return async.series(
        [
          callback =>
            self._buildTemplate('main.tex', owner_id, projectName, function(
              error,
              docLines
            ) {
              if (error != null) {
                return callback(error)
              }
              return ProjectCreationHandler._createRootDoc(
                project,
                owner_id,
                docLines,
                null,
                callback
              )
            }),
          callback =>
            self._buildTemplate(
              'references.bib',
              owner_id,
              projectName,
              function(error, docLines) {
                if (error != null) {
                  return callback(error)
                }
                return ProjectEntityUpdateHandler.addDoc(
                  project._id,
                  project.rootFolder[0]._id,
                  'references.bib',
                  docLines,
                  owner_id,
                  (error, doc) => callback(error)
                )
              }
            ),
          function(callback) {
            const universePath = Path.resolve(
              __dirname + '/../../../templates/project_files/universe.jpg'
            )
            return ProjectEntityUpdateHandler.addFile(
              project._id,
              project.rootFolder[0]._id,
              'universe.jpg',
              universePath,
              null,
              owner_id,
              callback
            )
          }
        ],
        error => callback(error, project)
      )
    })
  },

  _createRootDoc(project, owner_id, docLines, mainName = "main", callback) {
    if (callback == null) {
      callback = function(error, project) {}
    }
    if ( !mainName.includes(".") ) mainName = mainName + ".tex";
    return ProjectEntityUpdateHandler.addDoc(
      project._id,
      project.rootFolder[0]._id,
      mainName,
      docLines,
      owner_id,
      function(error, doc) {
        if (error != null) {
          logger.err(
            { err: error },
            'error adding root doc when creating project'
          )
          return callback(error)
        }
        return ProjectEntityUpdateHandler.setRootDoc(
          project._id,
          doc._id,
          error => callback(error, project)
        )
      }
    )
  },

  _buildTemplate(template_name, user_id, project_name, callback) {
    if (callback == null) {
      callback = function(error, output) {}
    }
    const self = this;
    return User.findById(user_id, 'first_name last_name', function(
      error,
      user
    ) {
      if (error != null) {
        return callback(error)
      }
      const templatePath = Path.resolve(
        __dirname + `/../../../templates/project_files/${template_name}`
      )
      return fs.readFile(templatePath, function(error, template) {
        if (error != null) {
          return callback(error)
        }
        const output = self._interpolateTemplate(
          project_name, user, template.toString()
        );
        return callback(null, output.split('\n'))
      })
    })
  },

  _interpolateTemplate: function(project_name, user, string) {
    const monthNames = ["January", "February", "March",
                        "April", "May", "June", "July",
                        "August", "September", "October",
                        "November", "December"
                       ];
    const data = {
      project_name: project_name,
      user: user,
      year: new Date().getUTCFullYear(),
      month: monthNames[new Date().getUTCMonth()]
    };
    return _.template(string, data);
  }
}

metrics.timeAsyncMethod(
  ProjectCreationHandler,
  'createBlankProject',
  'mongo.ProjectCreationHandler',
  logger
)

function __guard__(value, transform) {
  return typeof value !== 'undefined' && value !== null
    ? transform(value)
    : undefined
}
