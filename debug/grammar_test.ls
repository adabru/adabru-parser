#!/usr/bin/env lsc

# this script must be called from parent directory

require! [fs,child_process]
require! [minimist]

log = console.log
args = minimist process.argv.slice(2), {}

# compile files
for f in fs.readdirSync('./parser').filter((x)->x is /\.ls$/)
  f = "./parser/"+(f is /(.*)\.ls/)[1]
  if fs.statSync("#f.ls").mtime.getTime! > fs.statSync("#f.js").mtime.getTime!
    child_process.execSync "lsc -c #f.ls", encoding:'utf-8',stdio:'inherit'

# select file to parse
file = switch
  case args['create-oracle'], args.['verify'] then './grammar/informal_spec'
  case args._.length is 0 then './dev/grammar_test.data'
  default then args._.0

# create fresh grammar & parse
child_process.execSync "node ./parser/generator.js ./grammar/ab_markup.grammar -d -c ./html/js/build/ab_markup_grammar.json -i #file #{if args.nt? then "--nt #{args.nt}" else ""}", encoding:'utf-8',stdio:'inherit'

# after parse
abpv1 = require '../parser/abpv1.js'
grammar = require '../html/js/build/ab_markup_grammar.json'
input = fs.readFileSync file, {encoding: 'utf8'}

switch
  case args['create-oracle']
    ast <- abpv1.parse(input,grammar).then _
    parse_result = JSON.stringify ast
    fs.writeFileSync './dev/grammar_test.oracle', parse_result
  case args['verify']
    ast <- abpv1.parse(input,grammar).then _
    parse_result = JSON.stringify ast
    oracle = fs.readFileSync './dev/grammar_test.oracle', {encoding: 'utf8'}
    log if oracle is parse_result then 'Everything as oracle says' else 'Attention, does not match with oracle'
