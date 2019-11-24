const merge = require('webpack-merge')

const base = require('./webpack.config')

module.exports = merge(base, {
  mode: 'production',

  // Enable a full source map. Generates a comment linking to the source map
  devtool: 'source-map',

  output: {
    // Override filename to include hash for immutable caching
    filename: '[name]-[chunkhash].js'
  }
})
