import tables
import sets
import hashes

import patty

type
  NimyError* = object of Exception
  NimyActionError* = object of NimyError
  NimyGotoError* = object of NimyError

  sym* = string
  SymbolKind* {.pure.} = enum
    TermS
    NonTermS
    Nil
    Empty
  Symbol*[T] = object
    case kind*: SymbolKind
    of SymbolKind.TermS:
      term*: T
    of SymbolKind.NonTermS:
      nonTerm*: sym
    else:
      discard

  Rule*[T] = object
    left*: Symbol[T]
    right*: seq[Symbol[T]]

proc len*[T](r: Rule[T]): int =
  return r.right.len

proc `==`*[T](a, b: Symbol[T]): bool =
  if a.kind != b.kind:
    return false
  match a:
    TermS(term: t):
      return t == b.term
    NonTermS(nonTerm: nt):
      return nt == b.nonTerm
    _:
      return true

proc NonTermS*[T](nonTerm: sym): Symbol[T] =
  return Symbol[T](kind: SymbolKind.NonTermS, nonTerm: nonTerm)

proc Nil*[T](): Symbol[T] =
  return Symbol[T](kind: SymbolKind.Nil)

proc Empty*[T](): Symbol[T] =
  return Symbol[T](kind: SymbolKind.Empty)

proc TermS*[T](term: T): Symbol[T] =
  return Symbol[T](kind: SymbolKind.TermS, term: term)

type
  Grammar*[T] = object
    rules*: HashSet[Rule[T]]
    start*: Symbol[T]
    firstTable*: FirstTable[T]
    followTable*: FollowTable[T]

  FollowTable[T] = Table[Symbol[T], HashSet[Symbol[T]]]
  FirstTable[T] = Table[Symbol[T], HashSet[Symbol[T]]]

proc `$`*[T](ft: FollowTable[T]): string =
  result = "FollowTable:\n--------\n"
  for i, itms in ft:
    result = result & $i & ":" & $itms & "\n"
  result = result & "--------\n"

proc hash*[T](x: Symbol[T]): Hash =
  var h: Hash = 0
  h = h !& hash(x.kind)
  match x:
    TermS(term: s):
      h = h !& hash(s)
    NonTermS(nonTerm: s):
      h = h !& hash(s)
    _:
      discard
  return !$h

proc hash*[T](x: Rule[T]): Hash =
  var h: Hash = 0
  h = h !& hash(x.left)
  h = h !& hash(x.right)
  return !$h

proc `[]`[T](os: OrderedSet[T], idx: int): T {.inline.} =
  if os.len <= idx:
    raise newException(IndexError, "idx is too large.")
  for i, key in os:
    if i == idx:
      return key

proc newRule*[T](left: Symbol[T], right: varargs[Symbol[T]]): Rule[T] =
  assert left.kind == SymbolKind.NonTermS,
     "Right side of rule must be Non-Terminal Symbol."
  var rightSeq: seq[Symbol[T]] = @[]
  for s in right:
    rightSeq.add(s)

  result = Rule[T](left: left, right: rightSeq)

proc newRule*[T](left: Symbol[T], right: Symbol[T]): Rule[T] =
  assert left.kind == SymbolKind.NonTermS,
     "Right side of rule must be Non-Terminal Symbol."
  result = Rule[T](left: left, right: @[right])

proc initGrammar*[T](rules: HashSet[Rule[T]], start: Symbol[T]): Grammar[T] =
  result = Grammar[T](rules: rules, start: start)

proc initGrammar*[T](rules: openArray[Rule[T]],
                     start: Symbol[T]): Grammar[T] =
  result = initGrammar(rules.toSet, start)

proc filterRulesLeftIs*[T](g: Grammar[T], x: Symbol[T]): seq[Rule[T]] =
  result = @[]
  for r in g.rules:
    if r.left == x:
      assert (not (r in result)), "x in result."
      result.add(r)

proc isAugument*[T](g: Grammar[T]): bool =
  result = (g.start == NonTermS[T]("__Start__"))
  assert (g.filterRulesLeftIs(g.start).len != 0),
     "`g` is invalid gramer."

proc startRule*[T](g: Grammar[T]): Rule[T] =
  doAssert g.isAugument, "`g` is not augument gramer."
  let ret = g.filterRulesLeftIs(g.start)
  doAssert (ret.len == 1), "`g` is invalid augument gramer."
  for r in ret:
    result = r

proc symbolSet*[T](g: Grammar[T]): HashSet[Symbol[T]] =
  result.init()
  for r in g.rules:
    for s in r.right:
      result.incl(s)
  result.incl(g.start)

proc nonTermSymbolSet*[T](g: Grammar[T]): HashSet[Symbol[T]] =
  result.init()
  for r in g.rules:
    for s in r.right:
      if s.kind == SymbolKind.NonTermS:
        result.incl(s)
  result.incl(g.start)

proc containsOrIncl*[T](s: var HashSet[T], other: HashSet[T]): bool =
  result = true
  assert s.isValid, "The set `s` needs to be initialized."
  assert other.isValid, "The set `other` needs to be initialized."
  for item in other:
    result = result and containsOrIncl(s, item)

proc makeFirstTable[T](g: Grammar[T]): FirstTable[T] =
  result = initTable[Symbol[T], HashSet[Symbol[T]]]()
  for s in g.symbolSet:
    match s:
      NonTermS:
        var initSet: HashSet[Symbol[T]]
        initSet.init()
        result[s] = initSet
      TermS:
        result[s] = [s].toSet
      _:
        doAssert false, "There is a non-symbol in rules."

  for r in g.rules:
    if r.right.len == 0:
      result[r.left].incl(Empty[T]())

  var fCnt = true
  while fCnt:
    fCnt = false
    for r in g.rules:
      var fEmp = true
      for s in r.right:
        let newFst = result[r.left] + (result[s] - [Empty[T]()].toSet)
        if result[r.left] != newFst:
          fCnt = true
        result[r.left] = newFst
        if not result[s].contains(Empty[T]()):
          fEmp = false
          break
      if fEmp:
        if not result[r.left].containsOrIncl(Empty[T]()):
          fCnt = true

proc makeFollowTable[T](g: Grammar[T]): FollowTable[T] =
  doAssert g.firstTable.len != 0, "firstTable is nill."
  result = initTable[Symbol[T], HashSet[Symbol[T]]]()
  for s in g.nonTermSymbolSet:
    var initSet: HashSet[Symbol[T]]
    initSet.init()
    result[s] = initSet
  result[g.start].incl(Nil[T]())
  var fCnt = true
  while fCnt:
    fCnt = false
    for r in g.rules:
      var
        fEmpTail = true
        firstSyms: HashSet[Symbol[T]]
      firstSyms.init()
      # for sym in r.right.reversed
      for i in countdown(r.right.len - 1, 0):
        let sym = r.right[i]
        assert sym != Nil[T]()
        match sym:
          TermS:
            # renew meta data
            fEmpTail = false
            firstSyms = [sym].toSet
          NonTermS:
            # renew first table
            for f in firstSyms:
              let prevFC = fCnt
              fCnt = (not result[sym].containsOrIncl(f))
              fCnt = fCnt or prevFC
            if fEmpTail:
              for f in result[r.left]:
                let prevFC = fCnt
                fCnt = (not result[sym].containsOrincl(f))
                fCnt = fCnt or prevFC

            # renew meta data
            let fsts = g.firstTable[sym]
            if fsts.contains(Empty[T]()):
              for f in fsts:
                firstSyms.incl(f)
            else:
              fEmpTail = false
              firstSyms = fsts
          _:
            doAssert false, "There is other than Term or NonTerm in Rules."

proc augument*[T](g: Grammar[T]): Grammar[T] =
  let
    start = NonTermS[T]("__Start__")
    startRule = newRule(left = start, right = g.start)
  assert (not g.rules.contains(startRule)),
     "`g` is already augument. (the sym '__Start__' can't be used.)"
  var singleStart = initSet[Rule[T]]()
  singleStart.incl(startRule)
  let newRules = g.rules + singleStart
  result = initGrammar(newRules, start)
  result.firstTable = result.makeFirstTable
  result.followTable = result.makeFollowTable
