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
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
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
const { promisify } = require('util')
const _ = require('underscore')
const AnalyticsManger = require('../Analytics/AnalyticsManager')
const ProjectLocator = require('./ProjectLocator');
const ProjectDuplicator = require('./ProjectDuplicator');

const ProjectCreationHandler = {
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

    attributes.lastUpdatedBy = attributes.owner_ref = new ObjectId(owner_id)
    attributes.name = projectName
    const project = new Project(attributes)

    Object.assign(project, attributes)

    if (Settings.apis.project_history.displayHistoryForNewProjects) {
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
            project.spellCheckLanguage = user.ace.spellCheckLanguage;
            cb(err);
          }
        );
      }, (cb) => {
        // Globalize projects
        User.find({ _id: {$ne: attributes.owner_ref}}, {_id:1}, (err, docs) => {
          if ( err != null ) return cb(err);
          logger.log({owner: attributes.owner_ref, users: docs}, "globalizing project for owner");
          if ( docs.length ) {
            project.collaberator_refs = docs.map( doc => doc._id );
          }
          // docs.forEach( doc => project.collaberator_refs.push(doc._id) );
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
    return ProjectCreationHandler.createBlankProject(
      owner_id,
      projectName,
      function(error, project) {
        if (error != null) {
          return callback(error)
        }
        return ProjectCreationHandler._createRootDoc(
          project,
          owner_id,
          docLines,
          callback
        )
      }
    )
  },

  createBasicProject(owner_id, projectName, template = "mainbasic", callback) {
    if (callback == null) {
      callback = function(error, project) {}
    }
    const mainName = projectName
          .replace(/\s[a-zæøå]/g, match => match.toUpperCase() )
          .replace(/\s/g, "")
    return ProjectCreationHandler.createBlankProject(
      owner_id, projectName, function(error, project) {
        if (error != null) {
          return callback(error)
        }
        return ProjectCreationHandler._buildTemplate(
          template + ".tex",
          owner_id,
          projectName,
          function(error, docLines) {
            if (error != null) {
              return callback(error)
            }
            return ProjectCreationHandler._createRootDoc(
              project, owner_id, docLines, mainName, callback
            )
          }
        )
      }
    )
  },

  createExampleProject(owner_id, projectName, callback) {
    if (callback == null) {
      callback = function(error, project) {}
    }
    return ProjectCreationHandler.createBlankProject(
      owner_id,
      projectName,
      function(error, project) {
        if (error != null) {
          return callback(error)
        }
        return async.series(
          [
            callback =>
              ProjectCreationHandler._buildTemplate(
                'main.tex',
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
                    callback
                  )
                }
              ),
            callback =>
              ProjectCreationHandler._buildTemplate(
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
      }
    )
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
          logger.warn(
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

const promises = {
  createBlankProject: promisify(ProjectCreationHandler.createBlankProject)
}

ProjectCreationHandler.promises = promises

module.exports = ProjectCreationHandler
