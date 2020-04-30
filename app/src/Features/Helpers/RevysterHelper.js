const https = require("https");
const logger = require("logger-sharelatex");
const TagsHandler = require("../Tags/TagsHandler");
const ProjectCreationHandler = require("../Project/ProjectCreationHandler");
const UserGetter = require("../User/UserGetter");
const UserRegistrationHandler = require("../User/UserRegistrationHandler");
const fs = require("fs").promises;
const path = require("path");
const MAX_RETRIES = 10;
let RevysterHelper;

function promiseWrapMethods( callbackOwner ) {
  if ( callbackOwner.asyncProxy == undefined ) {

    let promiseWrappingHandler = {
      get: function(target, prop, reciever) {
        if ( typeof target[prop] !== "function" )
          return Reflect.get(...arguments);

        return function promiseWrappedMethod( ...args ) {
          return new Promise(( resolve, reject ) => {
            args.push( (err, ...results) => {
              if (err != null)
                reject(err);
              else
                resolve(results);
            });
            try {
              target[prop].apply( target, args );
            } catch (error) {
              reject(error);
            }
          });
        };
      }
    };

    callbackOwner.asyncProxy = new Proxy(
      callbackOwner, promiseWrappingHandler
    );
  }

  return callbackOwner.asyncProxy;
};

module.exports = RevysterHelper = {
  
  validateEmail: async(req, res, next) => {
    try {
      if ( await RevysterHelper.isEmailSubscribed(req.body.email) ) {
        logger.log("Email found on revyster's roster. Registering user.",
                   req.body.email);
        next();
      } else {
        logger.log("Email not on revyster's roster. Sending 404.",
                   req.body.email);
        res.status(404).send({
          'message': "Den email-adresse ser ikke ud til at være tilmeldt"
            + " revyster. Prøv en anden, eller skriv til en administrator."
        });
      }
    } catch (error) {
      logger.log("Error getting revyster's roster.");
      next(error);
    }
  },
  
  isEmailSubscribed: function(email) {
    let revysterMail = 'the.bentusi@gmail.com';
    let revysterPass = 'evogex';
    let addressSet = new Set();
    let queryBody
      = 'language=en&roster-email='
      + revysterMail.replace('@', '%40')
      + '&roster-pw='
      + revysterPass
      + '&SubscriberRoster=Visit+Subscriber+List';
    let options = {
      hostname: 'mailman.nbi.ku.dk',
      path: '/mailman/roster/revyster',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(queryBody)
      }
    };
    let lookForAddresses = (function* lookForAddresses() {
      let dataBuffer = [];
      let bufferSide = 0;
      let addressSet = new Set();
      while (true) {
        let chunk = yield addressSet;
        if ( chunk == undefined || chunk.toString == undefined )
          continue;
        dataBuffer[bufferSide] = chunk.toString();
        let otherSide = (bufferSide + 1) % 2;
        let matches = ( dataBuffer[otherSide] != null )
          ? dataBuffer[otherSide].concat(dataBuffer[bufferSide])
          : dataBuffer[bufferSide];
        let regexp = /<a href="..\/options\/revyster\/([^"]*)--at--([^"]*)">/g;
        let matchArr;
        while ((matchArr = regexp.exec(matches)) != null) {
          addressSet.add(matchArr[1] + "@" + matchArr[2]);
        }
        bufferSide = otherSide;
      }
    })();
    lookForAddresses.next();    // Gotta be primin'

    return new Promise( (resolve, reject) => {
      let req = https.request(options, function(res) {
        res.on('data', chunk => lookForAddresses.next(chunk));
        res.on('end', function() {
          var ref = res.statusCode;
          if ( 200 <= ref && ref < 300 ) {
            resolve( lookForAddresses.next().value.has(email.toLowerCase() ));
          } else {
            reject(res.headers);
          }
        });
        return res.on('error', function(error) {
          // something
          reject(error);
        });
      });
      logger.log("Calling " + options.hostname + options.path
                 + " for revyster's roster.");
      req.write(queryBody);
      req.end();
    });
  },
  
  async initDb( retryCount /*optional*/ ) {
    const parachute = Error("initDb parachute");
    let user = {};
    const createSingleDocumentProject = async(docName) => {
      // We look for docs in /app/templates/project_files
      const docPath = path.resolve(__dirname
                                   + '/../../../templates/project_files/'
                                   + docName
                                  );
      let docLines = (async() =>
                      (await fs.readFile(docPath, 'utf8')).split('\n'))();
      let newProject = promiseWrapMethods( ProjectCreationHandler )
          .createBlankProject(user._id, docName.replace(".tex", ""));
      
      [docLines, [newProject]] = await Promise.all([docLines, newProject]);
      logger.log({
        docPath: docPath,
        docLinesLength: docLines.length,
        newProject: newProject
      }, "createSingleProjectDocument creating root doc.");
      await promiseWrapMethods(ProjectCreationHandler)
        ._createRootDoc(newProject, user._id, docLines, docName);
      return newProject;
    };

    try {
      logger.log("Performing database initialisation for Revy-use.");
      [user] = await promiseWrapMethods( UserGetter )
          .getUser( {isAdmin: true}, {} );
      if (user == null) {
        logger.log(
          "No admin user to own anything yet. " +
            "Making kristoffer@levinhansen.dk an admin."
        );
        [user] = await promiseWrapMethods( UserRegistrationHandler )
          .registerNewUserAndSendActivationEmail("kristoffer@levinhansen.dk");
        user.isAdmin = true;
        user.save();
      } else {
        logger.log(user, "Admin user selected for template ownership.");
      }
      let userId = user._id.toString();
      let [tags] = await TagsHandler.promises.getAllTags({ $exists: true });
      let tagNames = tags.map( tag => tag.name );
      logger.log({ tagNames: tagNames }, "Found tags.");
      let taskArray = [];
      
      if ( !tagNames.includes("Kompilering") ) {
        logger.log({ tagNames: tagNames },
                   "Tag 'Kompilering' not found. Creating."
                  );
        taskArray.push(( async() => {
          let [[tag], project] = await Promise.all([
            TagsHandler.promises.createTag(userId, "Kompilering"),
            createSingleDocumentProject("revy.sty")
          ]);
          await TagsHandler.promises
            .addProjectToTag( userId, tag._id, project._id );
          logger.log({ userId: userId,
                       tagId: tag._id,
                       tagName: tag.name,
                       projectName: project.name
                     }, "New project"
                    );
        })());
      }
      
      if ( !tagNames.includes("Skabeloner") ) {
        logger.log({ tagNames: tagNames },
                   "Tag 'Skabeloner' not found. Creating.");
        taskArray.push( (async() => {
          let tagPromise = TagsHandler.promises
              .createTag( userId, "Skabeloner");
          await Promise.all(
            ["Sang.tex", "Sketch.tex"].map( async(name) => {
              let project = await createSingleDocumentProject(name);
              let [tag] = await tagPromise;
              logger.log({tag: tag}, "Skabeloner tag");
              await TagsHandler.promises
                .addProjectToTag( userId, tag._id, project._id );
              logger.log({ userId: userId,
                           tagId: tag._id,
                           tagName: tag.name,
                           projectName: project.name
                         }, "New project"
                        ); 
            }));
        })());
      }
      
      if (taskArray.length === 0) {
        logger.log("No init seems to need doing.");
      }
      await Promise.all(taskArray);
      
    } catch (error) {
      if (error.code && error.code == "ESOCKETTIMEOUT") {
        let count = ( retryCount ) ? retryCount : 0;
        if ( count < MAX_RETRIES ) RevysterHelper.initDB( count + 1 );
        else logger.err( {error: error,
                          stError: error.toString(),
                          retries: count
                         },
                         "Still getting timeout after retries."
                       );
      } else if (error !== parachute) {
        logger.err({ error: error, stError: error.toString() },
                   "RevysterInitDb"
                  );
      }
    }
  }
};
