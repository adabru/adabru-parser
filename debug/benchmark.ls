#!/usr/bin/env lsc

# use me with ../cli.ls

module.exports = exports = (grammar, file) ->
  log = console.log
  help = ->
    log '''
      benchmark.ls \033[1mbench\033[0m dir grammar_number file_number

        files used for benchmark are
          • <dir>/<grammar_number>.grammar
          • <dir>/<grammar_number>_<file_number>
          • <dir>/<grammar_number>.json (cached)
    '''

  # parse arguments
  args = []
  opt
  for arg in process.argv.slice (if process.argv.lsc? then 3 else 2)
    if arg.startsWith '-'
      if opt?
        args[opt] = true
      opt = arg.replace /(^-+)|(-$)/g, ''
      if arg.endsWith '-'
        args[opt] = '-'
        opt = null
    else if opt?
      args[opt] = arg
      opt = null
    else
      args.push arg
  if opt?
    args[opt] = true

  if args.0 isnt 'bench' or args.length isnt 4
    return help!

  require! [fs]
  exists = (path) ->
    try fs.accessSync path; true
    catch then false
  [_,d,g,f] = args
  error = (s) -> console.log '\033[31m'+s+'\033[39m'
  if not exists d
    return error "directory \033[1m#{d}\033[22m does not exist"
  if not exists "#d/#g.grammar"
    return error "grammar \033[1m#d/#g.grammar\033[22m does not exist"
  if not exists "#d/#{g}_#f"
    return error "file \033[1m#d/#{g}_#f\033[22m does not exist"

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

  _ =
    'q' : (a,i) --> a.slice!.sort((s,t) -> +s - +t)[Math.round (i/4) * (a.length-1)]
    '∑' : (a) -> a.reduce (a,x) -> a+x
    'μ' : (a) -> (1 / a.length) * _'∑' a

  boxplot = (a) ->
    let q = _'q'(a)
      i = [q(0), q(1), q(2), q(3), q(4)]
      μ = _'μ' a
      [...x,μx] = [...i,μ].map (ii) -> Math.round( (ii - i.0) / (i.4 - i.0) * 40 )
      s = ' '.repeat(μx) + '•' + Math.round μ
      s += ' '.repeat 40 - s.length
      res = i.0+'|'
      for c from 0 to s.length-1 then res += switch
        case c < x.1 then s[c]
        case c < x.2 then '\u001b[40m' + s[c] + '\u001b[49m'
        case c == x.2 then '\u001b[100m' + s[c] + '\u001b[49m'
        case c <= x.3 then '\u001b[40m' + s[c] + '\u001b[49m'
        default then s[c]
      res += '|'+i.4

  times = []
  pass = (i) ->
    if i<=10
      console.log 'Pass '+i+' of 10...'
      time1 = new Date!.getTime!
      ast <- abpv1.parse(_f,_g).then _
      time2 = new Date!.getTime!
      times.push time2 - time1
      console.log '                       '+boxplot times
      pass i+1
  pass 1

if process.argv.1.endsWith 'benchmark.ls'
  exports!
