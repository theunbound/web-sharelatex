const logger = require('logger-sharelatex')
const metrics = require('metrics-sharelatex')
const settings = require('settings-sharelatex')
const request = require('request')
const { promisifyAll } = require('../../util/promises')
const NotificationsBuilder = require('../Notifications/NotificationsBuilder')
const { V1ConnectionError } = require('../Errors/Errors')

const InstitutionsAPI = {
  getInstitutionAffiliations(institutionId, callback) {
    makeAffiliationRequest(
      {
        method: 'GET',
        path: `/api/v2/institutions/${institutionId.toString()}/affiliations`,
        defaultErrorMessage: "Couldn't get institution affiliations"
      },
      (error, body) => callback(error, body || [])
    )
  },

  getInstitutionLicences(institutionId, startDate, endDate, lag, callback) {
    makeAffiliationRequest(
      {
        method: 'GET',
        path: `/api/v2/institutions/${institutionId.toString()}/institution_licences`,
        body: { start_date: startDate, end_date: endDate, lag },
        defaultErrorMessage: "Couldn't get institution licences"
      },
      callback
    )
  },

  getInstitutionNewLicences(institutionId, startDate, endDate, lag, callback) {
    makeAffiliationRequest(
      {
        method: 'GET',
        path: `/api/v2/institutions/${institutionId.toString()}/new_institution_licences`,
        body: { start_date: startDate, end_date: endDate, lag },
        defaultErrorMessage: "Couldn't get institution new licences"
      },
      callback
    )
  },

  getUserAffiliations(userId, callback) {
    makeAffiliationRequest(
      {
        method: 'GET',
        path: `/api/v2/users/${userId.toString()}/affiliations`,
        defaultErrorMessage: "Couldn't get user affiliations"
      },
      (error, body) => callback(error, body || [])
    )
  },

  addAffiliation(userId, email, affiliationOptions, callback) {
    if (!callback) {
      // affiliationOptions is optional
      callback = affiliationOptions
      affiliationOptions = {}
    }

    const { university, department, role, confirmedAt } = affiliationOptions
    makeAffiliationRequest(
      {
        method: 'POST',
        path: `/api/v2/users/${userId.toString()}/affiliations`,
        body: { email, university, department, role, confirmedAt },
        defaultErrorMessage: "Couldn't create affiliation"
      },
      function(error, body) {
        if (error) {
          return callback(error, body)
        }
        if (!university) {
          return callback(null, body)
        }

        // have notifications delete any ip matcher notifications for this university
        NotificationsBuilder.ipMatcherAffiliation(userId).read(
          university.id,
          function(err) {
            if (err) {
              // log and ignore error
              logger.err(
                { err },
                'Something went wrong marking ip notifications read'
              )
            }
            callback(null, body)
          }
        )
      }
    )
  },

  removeAffiliation(userId, email, callback) {
    makeAffiliationRequest(
      {
        method: 'POST',
        path: `/api/v2/users/${userId.toString()}/affiliations/remove`,
        body: { email },
        extraSuccessStatusCodes: [404], // `Not Found` responses are considered successful
        defaultErrorMessage: "Couldn't remove affiliation"
      },
      callback
    )
  },

  endorseAffiliation(userId, email, role, department, callback) {
    makeAffiliationRequest(
      {
        method: 'POST',
        path: `/api/v2/users/${userId.toString()}/affiliations/endorse`,
        body: { email, role, department },
        defaultErrorMessage: "Couldn't endorse affiliation"
      },
      callback
    )
  },

  deleteAffiliations(userId, callback) {
    makeAffiliationRequest(
      {
        method: 'DELETE',
        path: `/api/v2/users/${userId.toString()}/affiliations`,
        defaultErrorMessage: "Couldn't delete affiliations"
      },
      callback
    )
  },

  addEntitlement(userId, email, callback) {
    makeAffiliationRequest(
      {
        method: 'POST',
        path: `/api/v2/users/${userId}/affiliations/add_entitlement`,
        body: { email },
        defaultErrorMessage: "Couldn't add entitlement"
      },
      callback
    )
  },

  removeEntitlement(userId, email, callback) {
    makeAffiliationRequest(
      {
        method: 'POST',
        path: `/api/v2/users/${userId}/affiliations/remove_entitlement`,
        body: { email },
        defaultErrorMessage: "Couldn't remove entitlement"
      },
      callback
    )
  }
}

var makeAffiliationRequest = function(requestOptions, callback) {
  if (!settings.apis.v1.url) {
    return callback(null)
  } // service is not configured
  if (!requestOptions.extraSuccessStatusCodes) {
    requestOptions.extraSuccessStatusCodes = []
  }
  request(
    {
      method: requestOptions.method,
      url: `${settings.apis.v1.url}${requestOptions.path}`,
      body: requestOptions.body,
      auth: { user: settings.apis.v1.user, pass: settings.apis.v1.pass },
      json: true,
      timeout: 20 * 1000
    },
    function(error, response, body) {
      if (error) {
        return callback(
          new V1ConnectionError('error getting affiliations from v1').withCause(
            error
          )
        )
      }
      if (response && response.statusCode >= 500) {
        return callback(
          new V1ConnectionError({
            message: 'error getting affiliations from v1',
            info: {
              status: response.statusCode,
              body: body
            }
          })
        )
      }
      let isSuccess = response.statusCode >= 200 && response.statusCode < 300
      if (!isSuccess) {
        isSuccess = requestOptions.extraSuccessStatusCodes.includes(
          response.statusCode
        )
      }
      if (!isSuccess) {
        let errorMessage
        if (body && body.errors) {
          errorMessage = `${response.statusCode}: ${body.errors}`
        } else {
          errorMessage = `${requestOptions.defaultErrorMessage}: ${
            response.statusCode
          }`
        }

        logger.warn(
          { path: requestOptions.path, body: requestOptions.body },
          errorMessage
        )
        return callback(new Error(errorMessage))
      }

      callback(null, body)
    }
  )
}
;[
  'getInstitutionAffiliations',
  'getUserAffiliations',
  'addAffiliation',
  'removeAffiliation'
].map(method =>
  metrics.timeAsyncMethod(
    InstitutionsAPI,
    method,
    'mongo.InstitutionsAPI',
    logger
  )
)

InstitutionsAPI.promises = promisifyAll(InstitutionsAPI)
module.exports = InstitutionsAPI
