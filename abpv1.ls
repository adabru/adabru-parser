#!/usr/bin/env lsc

# Thanks to Orlando Hill

require! [util, fs]

utils = do
  isString: (s) -> typeof s is 'string'
  isArray: Array.isArray
  hash: (s) ->
    hash = 0
    for i from 0 to s.length-1
      hash  = (((hash .<<. 5) - hash) + s.charCodeAt i) .|. 0
    hash
  flatten: (arr) -> [].concat.apply [], arr

print = (o, d=10) ->
  if window then console.log o # browser
  else      then console.log util.inspect o, {colors: true, depth: d}
stackTrace = (e) ->
  console.log "\033[31m#{e.stack}\033[39m"
todo = (s) ->
  console.log '\u001b[33mTODO: '+s+'\u001b[39m'
promiseThenCatch = (p, t, c) -> p.then(t).catch(c)

export class Ast
  (@name, @start, @end=start, @lookAhead=start, @status, @children=[]) ->

adabru_v1_parser = new
  @terminal = function T({x}, pos, node)
    [c] = node.params
    ast = new Ast '_T', pos
    pass = switch
      case utils.isString c
        for i from 0 to c.length-1
          if c[i++] != x[pos++] then break
        c[i-1] == x[pos-1]
      case utils.isArray c # char class
        pos++ < x.length
        and if c[0] == '^' then (c.slice 1).every ((cc) -> not (cc[0] <= x[pos-1] <= cc[1]))
                       else c.some ((cc) -> cc[0] <= x[pos-1] <= cc[1])
      case c is null # any
        pos++ < x.length
    ast.lookAhead = pos
    if !pass
      ast.status = 'fail'
    else
      ast.status = 'success'
      ast.end = ast.lookAhead
    return ast

  @nonterminal = !function NT(x, pos, node, [_call,c_ast])
    [sym, child] = node.params
    if not c_ast? then _call child.func, x, pos, child
    else
      ast = (new Ast sym) `Object.assign` c_ast{status, start, end, lookAhead}
      if c_ast.status == 'success' then ast.children = [c_ast]
      return ast

  @alternative = !function ALT(x, pos, node, [_call,c_ast,_local], [i=0, ast=new Ast '_ALT', pos]=[])
    [children] = node.params
    if not c_ast?
      _call children[i].func, x, pos, children[i]
    else
      ast.lookAhead >?= c_ast.lookAhead
      switch c_ast.status
        case 'success'
          ast{status, end} = c_ast
          ast.children = [c_ast]
          return ast
        case 'fail'
          if i < children.length-1
            _local [i+1, ast]
          else
            ast.status = 'fail'
            return ast

  @sequence = !function SEQ(x, pos, node, [_call,c_ast,_local], ast=new Ast '_SEQ',pos)
    [children] = node.params
    if not c_ast?
      _call children[ast.children.length].func, x, ast.end, children[ast.children.length]
    else
      ast.lookAhead >?= c_ast.lookAhead
      switch c_ast.status
        case 'success'
          ast.children ++= c_ast
          ast{end} = c_ast
          _local ast
          if ast.children.length == children.length
            ast.status = 'success'
            return ast
        case 'fail'
          ast.status = 'fail'
          return ast

  @optional = !function OPT(x, pos, node, [_call, c_ast])
    [child] = node.params
    if not c_ast? then _call child.func, x, pos, child
    else
      ast = new Ast '_OPT', pos, pos, c_ast.lookAhead, 'success'
      if c_ast.status == 'success'
        ast{end} = c_ast
        ast.children = [c_ast]
      return ast

  @star = !function STAR(x, pos, node, [_call, c_ast, _local], ast=new Ast '_STAR',pos,,,'success')
    [child] = node.params
    if not c_ast? then _call child.func, x, pos, child
    else
      ast{lookAhead} = c_ast
      switch c_ast.status
        case 'success'
          ast{end} = c_ast
          ast.children ++= c_ast
          _local ast
          _call child.func, x, ast.end, child
        case 'fail'
          return ast

  @plus = ~!function PLUS(x, pos, node, [_call, c_ast])
    if not c_ast? then _call @star, x, pos, node
    else
      c_ast.name = '_PLUS'
      if c_ast.status == 'success' and c_ast.children.length == 0
        c_ast.status = 'fail'
        c_ast.end = pos
      return c_ast

  @and = !function AND(x, pos, node, [_call, c_ast])
    [child] = node.params
    if not c_ast? then _call child.func, x, pos, child
    else then return new Ast '_AND', pos, pos, c_ast.lookAhead, c_ast.status, [c_ast]

  @not = !function NOT(x, pos, node, [_call, c_ast])
    [child] = node.params
    if not c_ast? then _call child.func, x, pos, child
    else return new Ast '_NOT', pos, pos, c_ast.lookAhead, {'fail':'success', 'success':'fail'}[c_ast.status], [c_ast]

  @void = !function VOID(x, pos, node, [_call, c_ast])
    [child] = node.params
    if not c_ast? then _call child.func, x, pos, child
    else then return new Ast '_VOID', pos, c_ast.end, c_ast.lookAhead, c_ast.status, [c_ast]

  @multipass = !function PASS({x,x_hash}, pos, node, [_call,c_ast,_local], first_ast)
    [children] = node.params
    switch
      case not c_ast?
        _call children[0].func, {x,x_hash}, pos, children[0]
      case not first_ast? and c_ast.status == 'fail'
        return new Ast '_PASS',pos,c_ast.end,c_ast.lookAhead,c_ast.status,[c_ast]
      case not first_ast? and c_ast.status == 'success'
        flatten = (x, ast) -->
          switch ast.name
            case '_T' then x.substring ast.start, ast.end
            case '_VOID' then ''
            default then (ast.children.map flatten x).join ''
        _local first_ast = new Ast '_PASS',pos,c_ast.end,c_ast.lookAhead,c_ast.status,[c_ast]
        first_ast.x = flatten x,c_ast
        first_ast.x_hash = x_hash+",#{pos},#{c_ast.end}:"+utils.hash first_ast.x
        _call children[1].func, {first_ast.x,first_ast.x_hash}, 0, children[1]
      case first_ast? and c_ast?
        first_ast
          ..children = [c_ast]
          ..status = c_ast.status
        return first_ast

  i = 0
  @parse = (stack, blocking_rate) ~>
    _call = (func, {x,x_hash}, pos, node) !-> stack.push [func,  {x,x_hash}, pos, node, void]
    _local = (s) -> stack[*-1][4] = s
    step = ->
      if stack[0] instanceof Ast then return stack[0]
      if stack[*-1] instanceof Ast then ast = stack.pop! else ast = void
      last = stack[*-1]
      res = last.0 last.1, last.2, last.3, [_call,ast,_local], last.4
      if res? then stack[*-1] = res
      null
    if blocking_rate is Infinity
      while not (ast=step!) then
      ast
    else
      (fulfill, reject) <- new Promise _
      parse_loop = ->
        while i++ < blocking_rate
          if (ast=step!)? then return fulfill ast
        i := 0
        setTimeout parse_loop
      parse_loop!


bind_grammar = (grammar, impl) ->
  visit = (node) ->
    switch
      # node has one child
      case node.params[0]?.func?
        visit node.params[0]
      # node has multiple children
      case node.params[0]?[0]?.func?
        node.params[0].map visit
      case node.func is 'nonterminal'
        let nt = node.params[0]
          if grammar[nt]?
            node.params = [nt, grammar[nt]]
            node{first_letter} = grammar[nt]
          else
            print "attention, nonterminal <#nt> is not defined"
            node.params = [{func:->{status:'fail'}, params:[]}]
    # replace function name with function reference
    node.func = impl[node.func]
  for symbol of grammar
    visit grammar[symbol]

decorate_parser = (parser, {
  memory={},
  first_letter_map=null
}={}) ->
  # multipass + optimization{packrat, first_letter_failing, first_letter_routing}
  parser._nonterminal ?= parser.nonterminal
  parser.nonterminal = parser._nonterminal
  parser._alternative ?= parser.alternative
  parser.alternative = parser._alternative
  let nt = parser.nonterminal
    parser.nonterminal = !function PACKRAT_NT({x,x_hash}, pos, node, [_call,c_ast])
      [sym, child] = node.params
      memory[x_hash] ?= {x}
      memory[x_hash][pos] ?= {}
      switch
        case memory[x_hash][pos][sym]? then return memory[x_hash][pos][sym]
        case c_ast? then return memory[x_hash][pos][sym]=c_ast
        default then _call nt, {x,x_hash}, pos, node
  let nt = parser.nonterminal
    parser.nonterminal = !function FIRST_LETTER_NT({x,x_hash}, pos, node, [_call,c_ast])
      [sym, child] = node.params
      switch
        case c_ast?
          return c_ast
        case not (node.first_letter.x ++ node.first_letter.ε).some ((interval) -> interval[0] <= x.charCodeAt(pos) <= interval[1])
          return new Ast sym,pos,pos,pos+1,'fail'
        default
          _call nt, {x,x_hash}, pos, node
  let alt = parser.alternative
    parser.alternative = !function FIRST_LETTER_ALT({x,x_hash}, pos, node, [_call,c_ast])
      [children] = node.params
      switch
        case c_ast?
          return c_ast
        default
          filtered_children = []
          for c in children
            if (c.first_letter.x ++ c.first_letter.ε).some((cc) -> cc[0] <= x.charCodeAt(pos) <= cc[1])
              filtered_children.push c
          if filtered_children.length is 0
            return new Ast '_ALT',pos,pos,pos+1,'fail'
          else
            _call alt, {x,x_hash}, pos, {func:alt,params:[filtered_children]}
  parser.regex = !function REGEX({x,x_hash}, pos, node)
    {regex} = node
    r = new RegExp regex, 'gy'
      ..lastIndex = pos
    if r.test x then return new Ast '_T',pos,r.lastIndex,x.length,'success'
    else             return new Ast '_T',pos,pos,x.length,'fail'
  parser

export parseSync = (x, grammar, options) ->
  parse x, grammar, Object.assign options ? {}, {blocking_rate: Infinity}
export parse = (x, grammar, options={}) ->
  options = {memory:{},startNT:Object.keys(grammar)[0],stack:[],blocking_rate:5e5} <<< options

  prepareParser = (grammar,options) ->
    # clone grammar for further processing
    grammar = JSON.parse JSON.stringify grammar

    # optimization: retrieve first letter ranges of NTs
    min = 0x0000
    max = 0xffff
    _ = {}
    _'¬' = (ccs) -> ccs.reduce(
      ([a,left],cc) ->
        if left < cc[0] then [a ++ [[left,cc[0]-1]], cc[1]+1] else [a, cc[1]+1]
      , [[],min]) |> ([a,left]) -> if left < max then a ++ [[left,max]] else a
    _'∪' = (...ccs) -> (ccs |> utils.flatten).sort( (s,t)->+s.0 - +t.0 ).reduce(
      ([...as,a],cc) ->
        switch
          case not a? then [cc]
          case a[1] >= cc[0]-1 then [...as,[a[0],a[1]>?cc[1]]]
          default then [...as,a,cc]
      , [])
    _'∩' = (...ccs) -> _'¬' _'∪' ...(ccs.map _'¬')
    first_letter = ({grammar,avoid_loops=true}:options,node) -->
      _first_letter = first_letter options
      {func,params:[p, ...ps]} = node
      switch func
        case 'terminal'
          node.first_letter =
            x:switch
              case utils.isString p                then [[p.charCodeAt(0), p.charCodeAt(0)]]
              case utils.isArray p and p[0] == '^' then _'¬' _'∪' (p.slice 1).map (cc) -> [cc.charCodeAt(0),cc.charCodeAt(1)]
              case utils.isArray p                 then _'∪' p.map (cc) -> [cc.charCodeAt(0),cc.charCodeAt(1)]
              case p is null                      then [[min,max]]
            ε:[]
        case 'alternative'
          node.first_letter = p.map(_first_letter).reduce (a,b) ->
            x: a.x `_'∪'` b.x
            ε: a.ε `_'∪'` b.ε
          ,{x:[],ε:[]}
        case 'sequence'
          node.first_letter = p.reduce(
            (a,child) ->
              if a.stop and avoid_loops then a else
                b = _first_letter child
                x: a.x `_'∪'` (a.ε `_'∩'` b.x)
                ε: a.ε `_'∩'` b.ε
                stop: b.ε.length == 0
            ,{x:[],ε:[[min,max]]}
          ){x,ε}
        case 'and'
          a = _first_letter p
          node.first_letter =
            x:[]
            ε: a.x `_'∪'` a.ε
        case 'not'
          a = _first_letter p
          node.first_letter =
            x:[]
            ε:[[min,max]]
        case 'optional','star'
          a = _first_letter p
          node.first_letter =
            x:a.x
            ε:[[min,max]]
        case 'void','plus'
          node.first_letter = _first_letter p
        case 'multipass'
          _first_letter p[1]
          node.first_letter = _first_letter p[0]
        case 'nonterminal'
          node.first_letter ?= _first_letter grammar[p]
    for k of grammar
      grammar[k].first_letter ? first_letter {grammar},grammar[k]
    for k of grammar
      first_letter {grammar,-avoid_loops},grammar[k]

    # optimization: regex substitution
    substitute_with_regex = (parent_precedence, node) -->
      precedence = ['terminal' 'star' 'plus' 'optional' 'sequence' 'alternative' 'and' 'not']
      {func,params:[p, ...ps]} = node
      swr = substitute_with_regex (precedence.indexOf(func) ? 0)
      child_regex = ((this_func, child) -->
        _child_func = child.func
        if swr(child)?
          r = child.regex
          if precedence.indexOf(func) < precedence.indexOf(if _child_func is 'terminal' and utils.isString child.params.0 and child.params.0.length > 0 then 'sequence' else _child_func)
            r = "(#r)"
          r
      ) func
      node.precedence = precedence.indexOf func
      node.regex = switch func
        case 'nonterminal' then void
        case 'void' then swr p ; void
        case 'multipass' then swr p.0 ; swr p.1 ; void
        case 'terminal'
          cc_string = (ccs) ->
            ccs.map((cc) -> "#{cc.0}#{if cc.0 != cc.1 then "-#{cc.1}" else ""}").join('').replace(/]/g, '\\]')
          switch
            case utils.isString p
              ['\\\\','\\[','\\|','\\*','\\+','\\?','\\(','\\)','\\.'].reduce ((a,x) -> a.replace new RegExp(x,'g'), x), p
            case utils.isArray p and p[0] == '^' then "[^#{cc_string(p.slice(1))}]"
            case utils.isArray p                 then "[#{cc_string(p)}]"
            case p is null                      then "[^]"
        case 'alternative'
          children = p.map (c) -> child_regex c
          if children.every((c) -> c?) then children.join('|')
          else                         then void
        case 'sequence'
          children = p.map (c) -> child_regex c
          if children.every((c) -> c?) then children.join('')
          else void
        case 'and' then (if (s=child_regex p)? then "(?=#s)")
        case 'not' then (if (s=child_regex p)? then "(?!#s)")
        case 'optional' then (if (s=child_regex p)? then "#s?")
        case 'star' then (if (s=child_regex p)? then "#s*")
        case 'plus' then (if (s=child_regex p)? then "#s+")
      if node.regex? then node.func = 'regex'
      node.regex
    for k of grammar
      substitute_with_regex 0,grammar[k]

    # add synthetic nonterminal to grammar
    grammar._start = {func: 'nonterminal', params: [options.startNT]}

    # link parsing functions to grammar, enable parser features
    parser = adabru_v1_parser
    parser = decorate_parser parser, options
    bind_grammar grammar, parser
    {parser,grammar}

  processAst = (ast,grammar) ->
    if ast.end != x.length then ast.status = 'fail' ; ast.error = 'did not capture whole input'
    if ast.status == 'fail' then return ast

    # postprocess ast, result is of form {name:'S', children:['adf', {name:'A', children:…}, '[a-z]']}
    pruned = (x, ast) -->
      switch ast.name
        case '_T'
          [x.substring ast.start, ast.end]
        case '_VOID'
          []
        case '_ALT', '_SEQ', '_VOID', '_AND', '_NOT', '_OPT', '_STAR', '_PLUS', '_NT'
          # concat all pruned children
          res = []
          for element in utils.flatten(ast.children.map pruned x)
            switch
              case utils.isString res[res.length-1] and utils.isString element
                res[res.length-1] += element
              case element != ''
                res ++= element
          res
        case '_PASS'
          pruned ast.x, ast.children[0]
        default # nonterminal
          if grammar[ast.name].flags?.pruned
            pruned x, ast.children[0]
          else
            * name: ast.name
              children: pruned x, ast.children[0]
    return pruned x,ast

  if options.blocking_rate is Infinity
    {parser,grammar:prepGrammar} = prepareParser grammar, options
    node = prepGrammar._start
    options.stack.push [node.func, {x,x_hash:utils.hash(x)}, 0, node, []]
    ast = parser.parse(options.stack, options.blocking_rate)
    return processAst ast, grammar
  else
    (fulfill, reject) <- new Promise _
    {parser,grammar:prepGrammar} = prepareParser grammar, options
    node = prepGrammar._start
    options.stack.push [node.func, {x,x_hash:utils.hash(x)}, 0, node, []]
    ast <- promiseThenCatch parser.parse(options.stack, options.blocking_rate), _, stackTrace
    fulfill processAst ast, grammar

export parseGrammar = require './generator.ls'

if process.argv.2?.endsWith 'abpv1.ls' and require.main === module
  (err, data) <- fs.readFile './abpv1.grammar', encoding: 'utf8', _
  if err? then throw err
  grammar <- promiseThenCatch (parseGrammar data), _, stackTrace
  console.log 'parsing base grammar ok'
  x = "S ← 'a'"
  ast <- promiseThenCatch (parse x, grammar), _, stackTrace
  console.log if ast.name isnt 'S' or ast.children.0.name isnt 'Rule' then '\033[31mparsing failed\033[39m' else 'parsing custom grammar ok'
  ast_sync = parseSync x, grammar
  console.log if (JSON.stringify ast) isnt (JSON.stringify ast_sync) then '\033[31masync parsing differs from sync\033[39m' else 'sync parse ok'
