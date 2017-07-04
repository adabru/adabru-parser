#!/usr/bin/env lsc

# helper functions
require! [util,tty,fs]
# repl = (context={}) ->
#   Object.assign require('repl').start('node> ').context, context
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
ellipsis = (s,l=10,r=15,e='…') ->
  m = Math.round l/2
  if s.length < r then s else "#{s.substr 0,m}#e#{s.substr -m,m}"
replace = (s, dic=[]) ->
  {inv,dim} = colors
  dic.reduce ((a,x) -> a.replace x.0, x.1), s
error = (s) ->
  console.log '\u001b[1m\u001b[31m'+s+'\u001b[39m\u001b[0m'
log = console.log
stackTrace = (e) ->
  error e.stack
write = (s) -> process.stdout.write s
todo = (s) ->
  console.log '\u001b[33mTODO: '+s+'\u001b[39m'
promiseThenCatch = (p, t, c) -> p.then(t).catch(c)


abpv1 = require './abpv1.ls'

memory_screen = ({memory, x, cursor}, repaint) ->
  x_hash = ''+util.hash x
  {f,b,inv,bold,dim} = colors
  line_lengths = (x.split '\n').map (s)->s.length
  line_and_col = (pos) ->
    for len,i in line_lengths
      if pos < len then return [i,pos] else pos -= len+1
  short_print = (ast, x, indent=0) ->
    s = ' '.repeat indent
    s += "#{ast.name} #{if ast.status == 'success' then '✔' else '✘'} #{ast.start} #{ast.end} #{ast.lookAhead} "
    s += x.substring ast.start, ast.end |>ellipsis _,50,60 |>f.92 |>b.100 |>replace _, [[/\n/g inv 'n']]
    s += x.substring ast.end, ast.lookAhead |>ellipsis _,20,16 |>f.3 |>b.100 |>replace _, [[/\n/g inv 'n']]
    log s
    if ast.status == 'fail' then for c in ast.children
      short_print c, x, indent+1
  cursor ?= {pos: {"#{x_hash}":0, '':0}, hash:x_hash}
  onkey = (d) ->
    i = j = cursor.pos[cursor.hash]
    switch (cursor.hash.match(/([^:]+)/g) || []).length
      case 0
        hashes = Object.keys(memory).filter((k)->k.startsWith x_hash)
        switch d
          case '\u001b[B' then cursor.hash = hashes[j] ; return onkey ''
          case '\u001b[C' then j++
          case '\u001b[D' then j--
        j = (j >? 0) <? hashes.length-1
        if d == '' or i != j
          cursor.pos[cursor.hash] = j
          repaint!
      default
        switch d
          case '\u001b[A'
            matches = cursor.hash.match /^(.+),[^,:]+,[^,:]+:[^:]+$|()/
            cursor.hash = matches[1] || matches[2] ; print cursor.hash ; return onkey ''
          case '\u001b[B'
            sub_hashes = Object.keys(memory).filter((k) -> k.startsWith(cursor.hash) && k != cursor.hash && +(k.substr(cursor.hash.length+1).match(/^([^,]+),/)[1]) == j)
            if sub_hashes.length > 0 then cursor.hash = sub_hashes.0
            return onkey ''
          case '\u001b[C' then j++
          case '\u001b[D' then j--
          case '0','1','2','3','4','5','6','7','8','9' then j = (j+d) .|. 0
          case '\u007f'
            s = ''+j
            j = if s.length<=1 then 0 else 0 .|. s.substr 0, s.length-1
        x = memory[cursor.hash].x
        j = (j >? 0) <? x.length-1
        if d == '' or i != j
          cursor.pos[cursor.hash] = j
          repaint!
  paint = ->
    log "#{bold '0-9 ← → BS'} move to character #{bold '↓ ↑'} change buffer\n"
    if not memory[x_hash]
      log "\nbuffer is empty! no memoization was made"
    else if (cursor.hash.match(/([^:]+)/g) || []).length is 0
      let j = cursor.pos[cursor.hash]
        hashes = Object.keys(memory).filter((k)->k.startsWith x_hash)
        log hashes.map((k,i)->if i == j then bold k else k).join('\n')
    else
      let j = cursor.pos[cursor.hash] then let [l,c] = line_and_col j, x = memory[cursor.hash].x
        stepDown = Object.keys(memory)
        .filter((k) -> k.startsWith(cursor.hash) && k != cursor.hash)
        .map((k) -> k.substr(cursor.hash.length).match(/([^,]+),([^:]+)/)[1,2])
        .filter((k) -> +k.0 == j)
        s = "#{bold j}/#{x.length}: line #{bold l}, col #{bold c}"
        s += "#{if stepDown.length>0 then " [↓ #{stepDown.0.0}:#{stepDown.0.1}#{if stepDown.length>1 then ", …#{stepDown.length - 1}" else ''}]" else ''}"
        s += "\n"
        s += "#{x.slice j-24>?0, j}#{bold x[j]}#{x.substr j+1, 24}" |>b.100 |>replace _, [[/\n/g "#{inv 'n'}\n"] [/ /g dim '·']]
        log s
        if memory[cursor.hash][j]? then for nt of memory[cursor.hash][j] then short_print memory[cursor.hash][j][nt], x

  {onkey, paint}

stack_screen = (stack) ->
  paint: ->
    print stack[*-3],1
    print stack[*-2],1
    print stack[*-1],1
  onkey: ->

stack_trace_screen = ({stack_trace, cursor}, repaint) ->
  {f,b,inv,bold,dim} = colors
  state =
    showLocal: false
  operator_map =
    'PACKRAT_NT':'🕮','FIRST_LETTER_NT':'🌔','FIRST_LETTER_ALT':'⎇','REGEX':'R','T':'T','PASS':'↺','PLUS':'+','STAR':'*','SEQ':'─','OPT':'?','VOID':':','NOT':'!','AND':'&','ALT':'|','NT':''
  paint = ->
    s = "#{bold '↑ ↓ → ← home end pg+ pg-'} move in trace #{bold 'l'} toggle locals\n\n"
    if (o=stack_trace[cursor.pos]) instanceof abpv1.Ast
      ast = o
      [func,{x,x_hash},pos,node,local] = cursor.stack[*-1]
    else
      [func,{x,x_hash},pos,node,local] = o
    if state.showLocal and not ast?
      log "\n#{util.inspect local, {+colors,depth:1}}"
      return
    symbols = cursor.stack.map ([f,x,pos,{params},local]) -> if f.name is 'NT' then params.0 else operator_map[f.name]
    # 13/16763 0/880 🌔 🕮 Document ─ ? 🌔 🕮 Tableofcontents : R
    s += "#{cursor.pos}/#{stack_trace.length} #pos/#{x.length} "
    switch ast?
      case true
        last_symbol = symbols.pop!
        s += "#{symbols.join ' '} "
        s += {'fail': f.1, 'success': f.2}[ast.status] last_symbol
      case false
        next_symbol = if func.name.endsWith 'NT' then node.params.0 else operator_map[func.name]
        s += "#{symbols.join ' '} #{f.3 next_symbol}"
    s += '\n\n'
    switch ast?
      case true
        # ✔ 0 5 880 [TOC]n…
        s += "#{if ast.status == 'success' then f.2 '✔' else f.1 '✘'} #{ast.start} #{ast.end} #{ast.lookAhead} \n\n"
        s += x.substring 0, ast.start |> ellipsis _, 50, 60  |>b.100|> replace _, [[/\n/g "#{inv 'n'}\n"] [/ /g dim '·']]
        s += x.substring ast.start, ast.end |> ellipsis _, 100, 120  |>b.100|>f.2|> replace _, [[/\n/g "#{inv 'n'}\n"] [/ /g dim '·']]
        s += x.substring ast.end, ast.lookAhead |> ellipsis _, 50, 60  |>b.100|>f.3|> replace _, [[/\n/g "#{inv 'n'}\n"] [/ /g dim '·']]
        s += x.substring ast.lookAhead |> ellipsis _, 50, 60  |>b.100|> replace _, [[/\n/g "#{inv 'n'}\n"] [/ /g dim '·']]
      case false
        # (:n | Block)*
        print_ops = ({func,node},nt=false) ->
          {params:p} = node
          precedence = ['REGEX','PLUS','STAR','OPT','VOID','NOT','AND','SEQ','ALT','FIRST_LETTER_ALT','PASS']
          switch func.name
            case 'NT', 'PACKRAT_NT', 'FIRST_LETTER_NT'
              if nt then print_ops(p.1 with node:p.1) else p.0
            case 'T' then (switch
              case util.isString p.0 then "'#{p.0}'"
              case util.isArray p.0
                "[" + p.0.map((cc) ->
                  switch
                    case cc == '^' then cc
                    case cc[0] == cc[1] then cc[0]
                    default then "#{cc[0]}-#{cc[1]}"
                ).join('') + "]"
              case p.0 is null then "."
              default then '⚠'
              ).replace /\n/g, inv 'n'
            case 'REGEX'
              node.regex |>f.95 |>replace _, [[/\n/g inv 'n'] [/ /g dim '·']]
            case 'STAR','PLUS','VOID','OPT','AND','NOT'
              c = print_ops p.0 with node:p.0
              if precedence.indexOf(func.name) < precedence.indexOf(p.0.func.name) then c = "(#c)"
              switch func.name
                case 'STAR' then "#c*"
                case 'PLUS' then "#c+"
                case 'VOID' then ":#c"
                case 'OPT' then "#c?"
                case 'AND' then "&#c"
                case 'NOT' then "!#c"
            case 'SEQ', 'ALT', 'FIRST_LETTER_ALT', 'PASS'
              cc = p.0.map (c) -> if precedence.indexOf(func.name) < precedence.indexOf(c.func.name) then "(#{print_ops c with node:c})" else print_ops c with node:c
              switch func.name
                case 'SEQ' then cc.join ' '
                case 'ALT', 'FIRST_LETTER_ALT' then cc.join ' | '
                case 'PASS' then cc.join ' ↺ '
            default then util.inspect p, {+colors,depth:1}
        s += print_ops {func, node}, func.name.endsWith 'NT'
        # [TOC]…
        s += '\n\n'
        s += x.substring 0, pos |>ellipsis _, 50, 60  |>b.100|>replace _, [[/\n/g "#{inv 'n'}\n"]]
        s += x.substring pos, pos+1 |>replace _, [[/\n/g "#{inv 'n'}\n"] [/ /g dim '·']] |>b.100|>f.2 |>bold
        s += x.substring pos+1, x.length |> ellipsis _, 50, 60  |>b.100|> replace _, [[/\n/g "#{inv 'n'}\n"]]
    log s
  onkey = (key) ->
    i = j = cursor.pos
    stepLeft = ->
      if j is 0 then return false
      j--
      if stack_trace[j] instanceof abpv1.Ast
        k = 1 ; jj = j ; while k > 0 then if stack_trace[--jj] instanceof abpv1.Ast then k++ else k--
        cursor.stack.push stack_trace[jj]
      else then cursor.stack.pop!
      true
    stepRight = ->
      if j is stack_trace.length - 1 then return false
      if stack_trace[j] instanceof abpv1.Ast then cursor.stack.pop! else cursor.stack.push stack_trace[j]
      j++
      true
    switch key
      case '\u001b[A'
        sl = cursor.stack.length
        if sl > 0 then while sl <= cursor.stack.length and stepLeft! then
      case '\u001b[B'
        if stack_trace[j] instanceof abpv1.Ast then stepRight!
        sl = cursor.stack.length
        if sl > 2
          while sl <= cursor.stack.length and stepRight! then
          stepLeft!
      case '\u001b[C' then stepRight!
      case '\u001b[D' then stepLeft!
      case 'l' then != state.showLocal ; return repaint!
      case '\u001b[5~'
        sl = cursor.stack.length ; i = 1
        stepLeft! ; while sl != cursor.stack.length and stepLeft! then i++
        if sl != cursor.stack.length then while i-- > 0 then stepRight!
      case '\u001b[6~'
        sl = cursor.stack.length ; i = 1
        stepRight! ; while sl != cursor.stack.length and stepRight! then i++
        if sl != cursor.stack.length then while i-- > 0 then stepLeft!
      case '\u001b[H'
        while stepLeft! then
      case '\u001b[F'
        while stepRight! then
    if i != j
      cursor.pos = j ; repaint!
  {paint, onkey}

inspect = (x, memory, stack, {running=false,stack_trace=null}) ->
  {bold} = colors
  @status =
    stacksize: 0
    starttime: new Date!.getTime!
    started: false
    running: running
    stack_trace: stack_trace
    cursor:
      memory:
        pos: {"#{util.hash x}":0, '':0}
        hash: ''+util.hash x
      stack_trace:
        pos: 0
        stack: []
  @screen =
    paint: ->
      todo 'better suggestions here than just going through the buffer, e.g. some statistically trained suggestions'
    onkey: ->
  @istream = if process.stdin.isTTY? then process.stdin else new tty.ReadStream fs.openSync '/dev/tty', 'r'
  @paint = (screen=true) ~>
    try
      write '\u001b[0;0H\u001b[K' + "#{bold 's'} stack #{bold 'm'} memory#{if @status.stack_trace? then " #{bold 't'} stack trace" else ""}#{if @status.running then " #{bold 'c'} cancel parsing [stack #{stack.length}]" else ""}  #{bold 'Ctrl-C'} leave"
      if screen
        process.stdout.write '\u001b[2;0H\u001b[J'
        @screen.paint!
    catch e
      log e
  @start = ~>
    log "Press #{bold 'd'} to start interactive debugging"
    @istream
      ..setEncoding 'utf8'
      ..setRawMode true
      ..resume!
      ..on 'data', @callback=(d) ~>
        switch d
          case 's'
            @screen = stack_screen stack, @paint
            @paint!
          case 'm'
            @screen = memory_screen {memory, x, cursor:@status.cursor.memory}, @paint
            @paint!
          case 't'
            if @status.stack_trace?
              @screen = stack_trace_screen {stack_trace:@status.stack_trace, cursor:@status.cursor.stack_trace}, @paint
              @paint!
          case 'd'
            if not @status.started
              != @status.started
              if @status.running then @interval = setInterval (~> @paint false), 1000
              write '\u001b7\u001b[?47h'
              @paint!
          case 'c'
            if @status.running
              stop = new abpv1.Ast 'INSPECTOR_STOP'
              stop.status = 'fail'
              stack.unshift stop
              log 'parsing was canceled.'
          case '\u0003'
            @end!
            log '^C'
            process.exit!
          default @screen.onkey d
  @stopped = ~>
    @status.running = false
    if @interval? then clearInterval @interval
  @end = ~>
    if @interval? then clearInterval @interval
    @istream.removeListener 'data', @callback
    @istream.pause!
    if @istream isnt process.stdin then @istream.end!
    if @status.started then write '\u001b[?47l\u001b8'
  @

export debug_parse = (x, grammar, parser_options={}, {print_ast=true,stack_trace=false,small_block=true,force_debug=false}={}) ->
  (fulfill) <- new Promise _
  memory = {name:'inspector_memory'}
  stack = []
    ..name = 'inspector_stack'
  if stack_trace?
    stack_trace := []
    stack._pop = stack.pop ; stack.pop = -> x = stack._pop! ; stack_trace.push x ; x
    stack._push = stack.push ; stack.push = (...arg) -> stack_trace.push ...arg ; stack._push ...arg
  if small_block then parser_options.blocking_rate ?= 1e4
  inspect_inst = new inspect x, memory, stack, {+running,stack_trace}
  inspect_inst.start!
  ast <- promiseThenCatch abpv1.parse(x, grammar, Object.assign parser_options, {memory,stack}), _, stackTrace
  inspect_inst.stopped!
  stack_trace?.push stack[0]
  if ast.status == 'fail'
    log 'parse failed'
    fulfill!
  else
    if not force_debug then inspect_inst.end!
    if print_ast then log printed_pruned_ast ast
    fulfill ast

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

# tests
if require.main === module
  memory = {name:'abcd'}
  (ast) <- promiseThenCatch debug_parse('S ← [ab]', require('./abpv1.json'), {memory}), _, stackTrace
  log ast
