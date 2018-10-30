var webpack = require("webpack")

module.exports = [{
  mode: 'development',
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
  mode: 'development',
  target: 'node',
  entry: './abpv1.ls',
  output: {
    libraryTarget: 'commonjs',
    filename: './abp.js'
  },
  module: {
    rules: [{
      test: /\.ls$/,
      loader: 'livescript-loader'
    }]
  }
}]
