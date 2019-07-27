/* eslint-disable
    camelcase,
    handle-callback-err,
    max-len,
    no-undef,
*/
// TODO: This file was created by bulk-decaffeinate.
// Fix any style issues and re-enable lint.
/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
let ProjectZipStreamManager
const archiver = require('archiver')
const async = require('async')
const logger = require('logger-sharelatex')
const ProjectEntityHandler = require('../Project/ProjectEntityHandler')
const ProjectGetter = require('../Project/ProjectGetter')
const FileStoreHandler = require('../FileStore/FileStoreHandler')

module.exports = ProjectZipStreamManager = {
  createZipStreamForMultipleProjects(project_ids, callback) {
    // We'll build up a zip file that contains multiple zip files

    if (callback == null) {
      callback = function(error, stream) {}
    }
    const archive = archiver('zip')
    archive.on('error', err =>
      logger.err(
        { err, project_ids },
        'something went wrong building archive of project'
      )
    )
    callback(null, archive)

    logger.log({ project_ids }, 'creating zip stream of multiple projects')

    const jobs = []
    for (let project_id of Array.from(project_ids || [])) {
      ;(project_id =>
        jobs.push(callback =>
          ProjectGetter.getProject(project_id, { name: true }, function(
            error,
            project
          ) {
            if (error != null) {
              return callback(error)
            }
            logger.log(
              { project_id, name: project.name },
              'appending project to zip stream'
            )
            return ProjectZipStreamManager.createZipStreamForProject(
              project_id,
              function(error, stream) {
                if (error != null) {
                  return callback(error)
                }
                archive.append(stream, { name: `${project.name}.zip` })
                return stream.on('end', function() {
                  logger.log(
                    { project_id, name: project.name },
                    'zip stream ended'
                  )
                  return callback()
                })
              }
            )
          })
        ))(project_id)
    }

    return async.series(jobs, function() {
      logger.log(
        { project_ids },
        'finished creating zip stream of multiple projects'
      )
      return archive.finalize()
    })
  },

  async createZipStreamForMultipleProjectFolders(project_ids, callback) {
    if (callback == null) {
      callback = function(error, stream) {};
    }
    var callbackToPromise = (cFunc, ...args) => {
      return new Promise( (resolve, reject) => {
        args.push( (error, ...rArgs) => {
          if (error == null)
            reject(error);
          else
            resolve(rArgs);
        });
        cFunc.call(this, args);
      });
    };

    // We will *not* build up a zip file that contains other zip files:
    var archive = archiver("zip");
    archive.on("error", err => {
      logger.err({
        err: err,
        project_ids: project_ids
      }, "something went wrong building archive of project");
    });
    logger.log({
      project_ids: project_ids
    }, "creating zip stream of multiple projects *not* in zip files");

    try {
      // If this works the first time, I will be amazed.
      var gatekeeper = Promise.resolve();
      project_ids.forEach( id => {
        gatekeeper = gatekeeper.then( () => {
          return callbackToPromise(ProjectGetter.getProject, id, {name: true});
        }).catch( error => {
          if ( error.gateError == null )
            error = { oer: error, gateError: true };
          throw error;
        }).then( project => {
          logger.log({
            project_id: id,
            name: project.name
          }, "appending project to zip stream");
          return callbackToPromise(
            this.addAllDocLinesToArchive, id,
            { archive: archive, basepath: project.name + "/" }
          );
        }).catch( error => {
          if ( error.gateError ) throw error;
          else
            logger.log({ error: error, project_id: id },
                       "error adding docs to zip stream");
        }).then( () => {
          return callbackToPromise(this.addAllFilesToArchive, id);
        }).catch( error => {
          if ( error.gateError ) throw error;
          else
            logger.log({ error: error, project_id: id},
                       "error adding files to zip stream");
        });
      });

      await gatekeeper;
      logger.log({
        project_ids: project_ids
      }, "finished creating zip of multiple projects");
      archive.finalize();
      
    } catch (error) {
      if (error.gateError) error = error.oer;
      callback(error);
    }
  },
  
  createZipStreamForProject(project_id, callback) {
    if (callback == null) {
      callback = function(error, stream) {}
    }
    const archive = archiver('zip')
    // return stream immediately before we start adding things to it
    archive.on('error', err =>
      logger.err(
        { err, project_id },
        'something went wrong building archive of project'
      )
    )
    callback(null, archive)
    return this.addAllDocsToArchive(project_id, archive, error => {
      if (error != null) {
        logger.error(
          { err: error, project_id },
          'error adding docs to zip stream'
        )
      }
      return this.addAllFilesToArchive(project_id, archive, error => {
        if (error != null) {
          logger.error(
            { err: error, project_id },
            'error adding files to zip stream'
          )
        }
        return archive.finalize()
      })
    })
  },

  addAllDocsToArchive(project_id, archiveOrOpts, callback) {
    if (callback == null) {
      callback = function(error) {}
    }
    let archive = ( archiveOrOpts.archive == null )
        ? archiveOrOpts
        : archiveOrOpts.archive;
    let basepath = ( archiveOrOpts.basepath != null )
        ? archiveOrOpts.basepath.replace( /\/*$/, "/")
        : "";
    return ProjectEntityHandler.getAllDocs(project_id, function(error, docs) {
      if (error != null) {
        return callback(error)
      }
      const jobs = []
      for (let path in docs) {
        const doc = docs[path]
        ;(function(path, doc) {
          path = path.replace(/^\/*/, basepath);
          return jobs.push(function(callback) {
            logger.log({ project_id }, 'Adding doc')
            archive.append(doc.lines.join('\n'), { name: path })
            return callback()
          })
        })(path, doc)
      }
      return async.series(jobs, callback)
    })
  },

  addAllFilesToArchive(project_id, archiveOrOpts, callback) {
    if (callback == null) {
      callback = function(error) {}
    }
    let archive = ( archiveOrOpts.archive == null )
        ? archiveOrOpts
        : archiveOrOpts.archive;
    let basepath = ( archiveOrOpts.basepath != null )
        ? archiveOrOpts.basepath.replace( /\/*$/, "/")
        : "";
    return ProjectEntityHandler.getAllFiles(project_id, function(error, files) {
      if (error != null) {
        return callback(error)
      }
      const jobs = []
      for (let path in files) {
        const file = files[path]
        ;((path, file) =>
          jobs.push(callback =>
            FileStoreHandler.getFileStream(project_id, file._id, {}, function(
              error,
              stream
            ) {
              if (error != null) {
                logger.warn(
                  { err: error, project_id, file_id: file._id },
                  'something went wrong adding file to zip archive'
                )
                return callback(err)
              }
              path = path.replace(/^\/*/, basepath);
              archive.append(stream, { name: path })
              return stream.on('end', () => callback())
            })
          ))(path, file)
      }
      return async.parallelLimit(jobs, 5, callback)
    })
  }
}
