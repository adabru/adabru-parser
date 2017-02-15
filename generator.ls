#!/usr/bin/env lsc

# helper functions
require! [util, fs, path]
promiseThenCatch = (p, t, c) -> p.then(t).catch(c)

module.exports = exports = (grammarText) ->
  abpv1Grammar = require './abpv1.json'
  abpv1 = require './abpv1.ls'
  inspector = require './inspector.ls'
  memory = {name: 'memory'}

  (fulfill,reject) <- new Promise _
  ast <- promiseThenCatch inspector.debug_parse(grammarText, abpv1Grammar, {memory}, {-print_ast}), _, reject
  if not ast? then return fulfill!

  # build grammar from raw ast
  grammar = {}
  toGrammar = (ast) ->
    switch ast.name
      case 'PASS' then func: 'multipass', params:[ast.children.map toGrammar]
      case 'ALT' then func: 'alternative', params:[ast.children.map toGrammar]
      case 'SEQ' then func: 'sequence', params:[ast.children.map toGrammar]
      case 'AND' then func: 'and', params: [toGrammar ast.children[0]]
      case 'NOT' then func: 'not', params: [toGrammar ast.children[0]]
      case 'VOID' then func: 'void', params: [toGrammar ast.children[0]]
      case 'OPT' then func: 'optional', params: [toGrammar ast.children[0]]
      case 'STAR' then func: 'star', params: [toGrammar ast.children[0]]
      case 'PLUS' then func: 'plus', params: [toGrammar ast.children[0]]
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
    grammar[nt]{func, params} = toGrammar rule.children[2]

  fulfill grammar
