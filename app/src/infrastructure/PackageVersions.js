// TODO: This file was created by bulk-decaffeinate.
// Sanity-check the conversion and remove this comment.
/*
 * decaffeinate suggestions:
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const version = {
  ace: '1.4.10', // Upgrade instructions: https://github.com/overleaf/write_latex/wiki/Upgrading-Ace
  fineuploader: '5.15.4'
}

module.exports = {
  version,

  lib(name) {
    if (version[name] != null) {
      return `${name}-${version[name]}`
    } else {
      return `${name}`
    }
  }
}
