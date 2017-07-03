#!/usr/bin/env lsc

do ->
  log = console.log
  help = ->
    log '''


    \033[1musage\033[0m: abp [options]

          -g <file>        use grammar <file>, defaults to
                           ./*.grammar if option empty or missing
          -i-, -i <file>   parse stdin or <file> with
                           specified grammar
          --nt <nt>        start with nonterminal <nt>, only
                           used when option -i is specified
                           defaults to first given rule in grammar
          --oo <file>      write parsed file to <file>. if <file> is
                           empty, ".json" is appended to original name
          -o-, -o <file>   write compiled parser to stdout or <file>
                           if <file> is empty, file is named
                           after grammar file
          -d               enter debug mode even on success

        abp \033[1mbench\033[0m dir grammar_number file_number

          files used for benchmark are
            • <dir>/<grammar_number>.grammar
            • <dir>/<grammar_number>_<file_number>
            • <dir>/<grammar_number>.json (cached)

        abp \033[1mverify\033[0m dir grammar_number file_number [--init]
          --init           create oracle from parse result

          files used for verifying are
            • <dir>/<grammar_number>.grammar
            • <dir>/<grammar_number>_<file_number>
            • <dir>/<grammar_number>.json (cached)
            • <dir>/<grammar_number>_<file_number>.oracle

    \033[1mExamples\033[0m
    printf "i == 5" | abp -g bash.grammar -i- --nt EXPRESSION
    abp -o jo.json
    abp verify ./debug/test_data 0 2
    abp bench ./debug/test_data 0 2

    '''

  # parse arguments
  argv = require('minimist') process.argv.slice(2), {}

  if argv._.0 is 'bench' then return (require './debug/benchmark.ls')!
  if argv._.0 is 'verify' then return (require './debug/verify.ls')!

  # invalid arguments
  if argv._.length > 0 or (Object.keys argv).length == 1 or not (Object.keys argv).every ((k) -> k in ['_','g','i','nt','oo','o','d'])
    return help!

  # define grammar
  require! [fs,path]
  error = (s) -> console.log '\033[31m'+s+'\033[39m'
  stackTrace = (e) -> error e.stack
  checkFile = (file, isok=->true, iswrong=->false) ->
    try fs.accessSync file; isok!
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
      files = fs.readdirSync path.dirname file
      base = path.basename file
      fuzzy = files.reduce (a,f) ->
        dist = levenshtein f, base
        if a[1] < dist then a else [f,dist]
      ,['',999]
      if fuzzy[1] <= base.length/2 then iswrong fuzzy[0] else iswrong!
  g = argv.g
  if not g? or g is true
    g = (fs.readdirSync '.').find (f) -> f.endsWith '.grammar'
    if not g?
      error 'no grammar specified and no ".grammar" file found in .'
      return help!
  else
    if not checkFile g, (->true), ((fuzzy)->error "grammar \033[1m#{g}\033[22m not found#{if fuzzy? then ", do you mean \033[1m#{fuzzy}\033[22m?" else ""}")
      return

  # generate (async)
  o = argv.o
  promiseThenCatch = (p, t, c) -> p.then(t).catch(c)
  if o is true then o = (path.basename g, '.grammar') + '.json'
  p = if o? and (checkFile o,(->true),(->false)) and (fs.statSync g).mtime.getTime! < (fs.statSync o).mtime.getTime!
    log 'generated parser is newer than grammar definition, using it'
    (fulfill) <- new Promise _
    fulfill JSON.parse fs.readFileSync o, {encoding: 'utf8'}
  else
    g_text = fs.readFileSync g, {encoding: 'utf8'}
    (fulfill,reject) <- new Promise _
    _o = o # scope issue
    grammar <- promiseThenCatch ((require './generator.ls') g_text), _, stackTrace
    o = _o
    switch o
      case void then
      case '-' then log JSON.stringify grammar, null, '  '
      default
        fs.writeFileSync o, JSON.stringify grammar
        log "written file \033[1m#{o}\033[22m"
    fulfill grammar
  g_compiled <- promiseThenCatch p, _, stackTrace

  # define input file
  i = argv.i
  p = null
  if i?
    res = ''
    if i is '-' then p = new Promise (fulfill) ->
      stdin = process.stdin
        ..setEncoding 'utf8'
        ..on 'readable', -> while chunk = stdin.read! then res += chunk
        ..on 'end', -> fulfill res
    else then p = checkFile i,
      -> new Promise (fulfill, reject) ->
        fs.readFile i, 'utf8', (err, res) ->
          if err then reject err else fulfill res
      (fuzzy) ->
        error "input file '#{i}' does not exist#{if fuzzy? then ", do you mean '#{fuzzy}'?" else ""}"
        null

  # parse input file (async)
  if p?
    s <- promiseThenCatch p, _, stackTrace
    ast <- promiseThenCatch (require './inspector.ls').debug_parse(s, g_compiled, (if argv.nt? then {startNT:argv.nt}), {+print_ast,+stack_trace,force_debug:argv.d}), _, stackTrace
    # save parsed file
    switch oo = argv.oo
      case void then
      case true then oo = "#i.json" ; fallthrough
      default
        (err) <- fs.writeFile oo, (JSON.stringify ast), _
        log "written file \033[1m#{oo}\033[22m"
