#!/usr/bin/env lsc

module.exports = exports = (grammar, input, basepath, bInit) ->
  log = console.log
  help = ->
    log '''
      verify.ls verify dir grammar_number file_number [--init]
        --init           create oracle from parse result

        files used for verifying are
          • <dir>/<grammar_number>.grammar
          • <dir>/<grammar_number>_<file_number>
          • <dir>/<grammar_number>.json (cached)
          • <dir>/<grammar_number>_<file_number>.oracle
    '''

  argv = require('minimist') process.argv.slice(2), {}

  if argv._.0 isnt 'verify' or argv._.length isnt 4
    return help!

  require! [fs]
  exists = (path) ->
    try fs.accessSync path; true
    catch then false
  [_,d,g,f] = argv._
  error = (s) -> console.log '\033[31m'+s+'\033[39m'
  if not exists d
    return error "directory \033[1m#{d}\033[22m does not exist"
  if not exists "#d/#g.grammar"
    return error "grammar \033[1m#d/#g.grammar\033[22m does not exist"
  if not exists "#d/#{g}_#f"
    return error "file \033[1m#d/#{g}_#f\033[22m does not exist"
  if not argv.init and not exists "#d/#{g}_#f.oracle"
    return error "oracle for file \033[1m#d/#{g}_#f\033[22m does not yet exist"

  # get grammar
  promiseThenCatch = (p, t, c) -> p.then(t).catch(c)
  stackTrace = (e) -> error e.stack
  p = if exists "#d/#g.json" and (fs.statSync "#d/#g.grammar").mtime.getTime! < (fs.statSync "#d/#g.json").mtime.getTime!
    (fulfill) <- new Promise _
    fulfill JSON.parse fs.readFileSync "#d/#g.json", {encoding: 'utf8'}
  else
    (fulfill,reject) <- new Promise _
    g_text = fs.readFileSync "#d/#g.grammar", {encoding: 'utf8'}
    g_json <- promiseThenCatch ((require '../generator.ls') g_text), _, stackTrace
    fs.writeFileSync "#d/#g.json", JSON.stringify g_json
    log "written file \033[1m#d/#g.json\033[22m"
    fulfill g_json
  _g <- promiseThenCatch p, _, stackTrace

  # get file
  _f = fs.readFileSync "#d/#{g}_#f", {encoding: 'utf8'}

  # parse
  abpv1 = require '../abpv1.ls'
  if argv.init
    p = (require '../inspector.ls').debug_parse _f, _g, null, {+print_ast,+stack_trace}
  else
    p = abpv1.parse _f,_g
  ast <- promiseThenCatch p, _, stackTrace
  parse_result = JSON.stringify ast

  # create or check with oracle
  if argv.init
    fs.writeFileSync "#d/#{g}_#f.oracle", parse_result
  else
    _o = fs.readFileSync "#d/#{g}_#f.oracle", {encoding: 'utf8'}
    log if _o is parse_result then 'Everything as oracle says' else 'Attention, does not match with oracle'

if process.argv.1.endsWith 'verify.ls'
  exports!
