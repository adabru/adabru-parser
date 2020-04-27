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

  if args.0 isnt 'verify' or args.length isnt 4
    log 'invalid arguments'
    return help!

  require! [fs]
  exists = (path) ->
    try fs.accessSync path; true
    catch then false
  [_,d,g,f] = args
  error = (s) -> console.error "\033[31m#{s}\n#{new Error!.stack}\033[39m"
  if not exists d
    return error "directory \033[1m#{d}\033[22m does not exist"
  if not exists "#d/#g.grammar"
    return error "grammar \033[1m#d/#g.grammar\033[22m does not exist"
  if not exists "#d/#{g}_#f"
    return error "file \033[1m#d/#{g}_#f\033[22m does not exist"
  if not args.init and not exists "#d/#{g}_#f.oracle"
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
  if args.init
    p = (require '../inspector.ls').debug_parse _f, _g, null, {+print_ast,+stack_trace}
  else
    p = abpv1.parse _f,_g
  ast <- promiseThenCatch p, _, stackTrace
  parse_result = JSON.stringify ast

  # create or check with oracle
  if args.init
    fs.writeFileSync "#d/#{g}_#f.oracle", parse_result
  else
    _o = fs.readFileSync "#d/#{g}_#f.oracle", {encoding: 'utf8'}
    if _o is parse_result
      log 'Everything as oracle says'
    else
      # print pretty diff, cf inspector.ls
      require! [util]
      colors = let e = ((e1,e2,s) --> "\u001b[#{e1}m#{s}\u001b[#{e2}m")
        b = [] ; for i in [0 to 7] then b[i]=e("4#i","49") ; for i in [100 to 107] then b[i]=e(i,"49")
        f = [] ; for i in [0 to 7] then f[i]=e("3#i","39") ; for i in [90 to 97] then f[i]=e(i,"39")
        {f,b,inv:e('07','27'), pos:e('27','07'), bold:e('01',22), dim:e('02',22), reset:e('00','00')}
      printed_pruned_ast = (ast) ->
        {f,b,inv,dim} = colors
        short_print = (prefix, ast) ->
          if util.isString ast
            s = (b.100 f.92 ast).replace(/\n/g, inv 'n')
          else
            s = f.3 ast.name
            abbr = ast.name.substr 0,2
            prefix += (dim f.3 abbr) + ' '
            if ast.children.length == 1
              s += ' ' + short_print prefix, ast.children.0
            else then for c in ast.children
              s += '\n' + prefix + (short_print prefix, c)
            s
        short_print '',ast
      pretty = printed_pruned_ast ast
      oracle_pretty = printed_pruned_ast JSON.parse _o
      # levenshtein line diff
      u = pretty.split '\n'
      v = oracle_pretty.split '\n'

      # dynamic programming with backtracking, start with mapping (u₀=ε, …, uₙ=v) → v₀=ε
      cost = [0 to u.length + 1]
      backtracking = [0 to u.length + 1].map (_, i) -> if i is 0 then ['_'] else ['D']

      # build 'table' up until (u₀=ε, …, uₙ=v) → vₙ=v
      # i\j     ε  u₁ …  uₙ
      # ε      [0  1  …  n ] = cost, i=0
      # v₁     [1  …       ] = cost, i=1
      # …
      # vₘ               _ x = optimum
      #
      # see https://github.com/hiddentao/fast-levenshtein/blob/master/levenshtein.js for optimization
      #
      # insertion = add from v
      # deletion = add from u
      # substitution = add from both
      #
      for i from 1 to v.length + 1
        # previous row
        _cost = cost.slice!

        cost[0] = _cost[0] + 1
        backtracking[0].push 'I'
        for j from 1 to u.length + 1
          substitutionCost = cost[j] = _cost[j-1] + if u[j-1] is v[i-1] then 0 else 5 # actually not allowed
          insertionCost = _cost[j] + 1
          deletionCost = cost[j-1] + 1
          cost[j] = Math.min substitutionCost, insertionCost, deletionCost
          backtracking[j].push if substitutionCost is cost[j] then 'S' else if insertionCost is cost[j] then 'I' else 'D'

      # backtrace and create diff
      i_u = u.length
      i_v = v.length
      diff = ''
      greyout = (s) -> s .replace(/\u001b\[3[1-6]m/g, '\u001b[37m') .replace(/\u001b\[9[1-6]m/g, '\u001b[97m')
      while backtracking[i_u][i_v] isnt '_'
        switch backtracking[i_u][i_v]
          | 'S'
            diff = (greyout u[i_u - 1]) + '\n' + diff
            i_u--
            i_v--
          | 'I'
            diff = 'oracl ' + v[i_v - 1] + '\n' + diff
            i_v--
          | 'D'
            diff = 'newer ' + u[i_u - 1] + '\n' + diff
            i_u--

      log 'Attention, does not match with oracle, showing diff:'
      log diff

if process.argv.1.endsWith 'verify.ls'
  exports!
