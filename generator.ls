#!/usr/bin/env lsc

# helper functions
require! [util, fs, path]
repl = (context={}) ->
  Object.assign require('repl').start('node> ').context, context
util.hash = (s) ->
  hash = 0
  for i from 0 to s.length-1
    hash  = (((hash .<<. 5) - hash) + s.charCodeAt i) .|. 0
  hash
print = (o, d=10) ->
  console.log util.inspect o, {colors: true, depth: d}
colors = let e = ((e1,e2,s) --> "\u001b[#{e1}m#{s}\u001b[#{e2}m")
    b = [] ; for i in [0 to 7] then b[i]=e("4#i","49") ; for i in [100 to 107] then b[i]=e(i,"49")
    f = [] ; for i in [0 to 7] then f[i]=e("3#i","39") ; for i in [90 to 97] then f[i]=e(i,"39")
    {f,b,inv:e('07','27'), pos:e('27','07'), bold:e('01',22), dim:e('02',22), reset:e('00','00')}
error = (s) ->
  console.log '\u001b[1m\u001b[31m'+s+'\u001b[39m\u001b[0m'
log = (s, newline=true) ->
  if newline then console.log s else process.stdout.write s
todo = (s) ->
  console.log '\u001b[33mTODO: '+s+'\u001b[39m'
get_stdin = ->
  res = ''
  new Promise (resolve) ->
    stdin = process.stdin
    stdin.setEncoding 'utf8'
    stdin.on 'readable', ->
      while chunk = stdin.read! then res += chunk
    stdin.on 'end', ->
      resolve res
check_file = (file_path, isok=->true, isempty=->false, iswrong=->false) ->
  if not file_path? then return isempty!
  try
    fs.accessSync file_path
    isok!
  catch
    levenshtein = (s,t) -> # edit distance
      switch
        case s == t then return 0
        case s == '' then return t.length
        case t == '' then return s.length

      v0 = [0 to t.length]
      v1 = []
      for i from 0 to s.length-1
        v1[0] = i+1
        for j from 0 to t.length-1
          cost = if s[i] == t[j] then 0 else 1
          v1[j+1] =   v1[j]+1   <?   v0[j+1]+1   <?   v0[j]+cost
        v0 = v1.slice!
      v1[t.length]
    fuzzy_files = fs.readdirSync path.dirname file_path
    let base = path.basename file_path
      suggestion = fuzzy_files.reduce (a,f) ->
        let dist = levenshtein f, base
          if a[1] < dist then a else [f,dist]
      ,['',999]
      if suggestion[1] <= base.length/2 then iswrong suggestion[0] else iswrong!
help = ->
  console.log '''


  \u001b[1musage\u001b[0m: abpv1 apple_banana.grammar OPTIONS

      -i <file>   parse <file> with specified grammar
                  or stdin if <file> is not given
      --nt <nt>   start with nonterminal <nt>, only
                  used when option -i is specified
                  defaults to first given rule in grammar
      -c <file>   write compiled parser to <file>, if <file>
                  is not given, it is written to stdout
      -d          enter debug mode even on success
      --help

  \u001b[1mExamples\u001b[0m
  echo "i == 5" | abpv1 bash.grammar -i --nt EXPRESSION
  abpv1 regex.grammar -c > jo.json

  '''

# show help
argv = require('minimist') process.argv.slice(2), {}
if argv.help
  help!
  return

# check grammar newer than generated parser
grammar_up_to_date = check_file argv.c and check_file argv._[0] and (fs.statSync argv._[0]).mtime.getTime! < (fs.statSync argv.c).mtime.getTime!
inspector = require './inspector.js'
grammar_get = if grammar_up_to_date
  (fulfill) <- new Promise _
  log 'The generated parser is newer than the grammar definition, using it'
  abpv1 = require './abpv1.js'
  fulfill JSON.parse fs.readFileSync argv.c, {encoding: 'utf8'}
else
  (fulfill) <- new Promise _
  # read grammar file
  valid = check_file argv._[0],
    ->
      true
    ->
      error 'no grammar file specified'
      help!
      false
    (suggestion) ->
      error "grammar file '#{argv._[0]}' does not exist"
      if suggestion? then log "did you mean '#{colors.bold suggestion}'?"
      help!
      false
  if not valid then return
  input = fs.readFileSync argv._[0], {encoding: 'utf8'}

  # parse  grammar
  abpv1_grammar = require './abpv1.json'
  abpv1 = require './abpv1.js'
  memory = {name: 'memory'}

  ast <- inspector.debug_parse(input, abpv1_grammar, {memory}, {-print_ast}).catch(log).then(_)
  if not ast? then return

  # build grammar from raw ast
  grammar = {}
  to_grammar = (ast) ->
    switch ast.name
      case 'PASS' then func: 'multipass', params:[ast.children.map to_grammar]
      case 'ALT' then func: 'alternative', params:[ast.children.map to_grammar]
      case 'SEQ' then func: 'sequence', params:[ast.children.map to_grammar]
      case 'AND' then func: 'and', params: [to_grammar ast.children[0]]
      case 'NOT' then func: 'not', params: [to_grammar ast.children[0]]
      case 'VOID' then func: 'void', params: [to_grammar ast.children[0]]
      case 'OPT' then func: 'optional', params: [to_grammar ast.children[0]]
      case 'STAR' then func: 'star', params: [to_grammar ast.children[0]]
      case 'PLUS' then func: 'plus', params: [to_grammar ast.children[0]]
      case 'NT' then func: 'nonterminal', params: [ast.children[0]]
      case 'T'
        func: 'terminal'
        params: switch ast.children[0][0]
            case '.' then [null]
            case '\''
              t = ast.children[0].substr 1, ast.children[0].length-2
              specials = '\\b':'\b', '\\f':'\f', '\\n':'\n', '\\O':'\O', '\\r':'\r', '\\t':'\t', '\\v':'\v', '\\\'':'\'', '\\\\':'\\'
              i = 0 ; while  i < t.length-1
                if specials[t.substr i,2]? then t = t.substring(0,i) + specials[t.substr i,2] + t.substring i+2
                i++
              [t]
            case '['
              specials = '\\b':'\b', '\\f':'\f', '\\n':'\n', '\\O':'\O', '\\r':'\r', '\\t':'\t', '\\v':'\v', '\\]':']', '\\\\':'\\'
              t = ast.children[0].substr 1, ast.children[0].length-2
              i = 0 ; while  i < t.length-1
                if specials[t.substr i,2]? then t = t.substring(0,i) + specials[t.substr i,2] + t.substring i+2
                i++
              res = []
              i = 0
              if t[i] == '^' then res ++= t[i++]
              while t[i]? then switch
                case t[i+1] == '-' and t[i+2]? then res ++= t[i]+t[(i+=3)-1]
                default then res ++= t[i]+t[i++]
              [res]
  for rule in ast.children
    flags = {}
    nt = rule.children[0].children[0]
    if rule.children[1] == '↖' then flags.pruned = true
    grammar[nt] = flags: flags
    grammar[nt]{func, params} = to_grammar rule.children[2]

  # write parser to file
  switch argv.c
    case true then log JSON.stringify grammar
    case void then
    default
      fs.writeFileSync argv.c, JSON.stringify grammar
      log "written file '#{colors.bold that}'"

  fulfill grammar

# parse/interpret user specified input with fresh grammar
(grammar) <- grammar_get.catch(log).then _
promise = switch argv.i
  case true
    get_stdin!
  case void then
  default
    check_file argv.i,
      -> new Promise (fulfill, reject) ->
        fs.readFile argv.i, 'utf8', (err, res) ->
          if err then reject err else fulfill res
      ->
      (suggestion) !->
        error "input file '#{argv.i}' does not exist"
        if suggestion? then log "did you mean '#{colors.bold suggestion}'?"
s <- promise?.catch(log).then _
ast <- inspector.debug_parse(s, grammar, (if argv.nt? then {startNT:argv.nt}), {+print_ast,+stack_trace,force_debug:argv.d}).catch(log).then _
