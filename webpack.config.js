var webpack = require("webpack")

module.exports = [{
  target: 'node',
  entry: './cli.ls',
  output: {
    filename: './cli.js'
  },
  module: {
    rules: [{
      test: /\.ls$/,
      loader: 'livescript-loader'
    }]
  },
  plugins: [
    new webpack.BannerPlugin({banner: '#!/usr/bin/env node', raw: true })
  ]
},{
  target: 'node',
  entry: './abpv1.ls',
  output: {
    library: 'abp',
    filename: './abp.js'
  },
  module: {
    rules: [{
      test: /\.ls$/,
      loader: 'livescript-loader'
    }]
  }
}]
