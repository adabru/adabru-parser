#!/usr/bin/env lsc

# call me from parent directory

require! [child_process,fs]

# compile files
for f in fs.readdirSync('./parser').filter((x)->x is /\.ls$/)
  f = "./parser/"+(f is /(.*)\.ls/)[1]
  if fs.statSync("#f.ls").mtime.getTime! > fs.statSync("#f.js").mtime.getTime!
    child_process.execSync "lsc -c #f.ls", encoding:'utf-8',stdio:'inherit'

child_process.execSync 'node ./parser/generator.js ./grammar/ab_markup.grammar -c ./html/js/build/ab_markup_grammar.json', encoding:'utf-8',stdio:'inherit'

abpv1 = require '../parser/abpv1.js'
grammar = require '../html/js/build/ab_markup_grammar.json'
document = fs.readFileSync (process.argv[2] ? './dev/benchmark_test.data'), 'utf8'

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
    ast <- abpv1.parse(document,grammar).then _
    time2 = new Date!.getTime!
    times.push time2 - time1
    console.log '                       '+boxplot times
    pass i+1
pass 1
