## Copy propagation/elimination pass implementation
##
## The basic idea behind this pass is that the middle-end (AST -> Bytecode / "Niche") generates a lot of unnecessary
## copy instructions. We can safely* eliminate these unnecessary copies if we can prove that the copied destination
## is unworthy of copying (it is never mutated AND it is locally defined)
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[sets]
import pkg/bali/runtime/compiler/madhyasthal/[pipeline, ir]

const MutationCausingOps = {
  InstKind.LoadNumber, InstKind.LoadString, InstKind.LoadNull, InstKind.LoadUndefined,
  InstKind.LoadBytecodeCallable, InstKind.LoadBoolean, InstKind.Add, InstKind.Mult,
  InstKind.Divide, InstKind.Sub,
}

func scanAllCopies*(pipeline: pipeline.Pipeline): HashSet[Copy] =
  var copies = initHashSet[Copy]()

  for i, inst in pipeline.fn.insts:
    case inst.kind
    of InstKind.Copy:
      copies.incl(Copy(source: inst.args[0].vreg, dest: inst.args[1].vreg))
    else:
      discard

  ensureMove(copies)

func scanAllMutations*(pipeline: pipeline.Pipeline): HashSet[Mutation] =
  var muts = initHashSet[Mutation]()

  for i, inst in pipeline.fn.insts:
    if inst.kind notin MutationCausingOps:
      continue

    # TODO: Make a function like `dest(Inst)` which lets you check
    # which register an operation can mutate
    if inst.args[1].kind == avkPos:
      muts.incl(Mutation(reg: inst.args[1].vreg, inst: uint32(i)))

  ensureMove(muts)

func eliminateUnmutatedCopies*(
    pipeline: pipeline.Pipeline, copies: HashSet[Copy]
): HashSet[Copy] =
  let muts = scanAllMutations(pipeline)
  var unmutated = initHashSet[Copy]()

  for copy in copies:
    for mut in muts:
      if mut.reg == copy.dest:
        # We can't eliminate this, it's mutated further.
        # Any attempts to eliminate this copy will cause semantic breakage.
        continue

      if copy.source notin pipeline.info.esc.locals:
        # debugecho "Can't optimize escapee %" & $copy.source & " -> %" & $copy.dest
        # If the register is not locally owned, we cannot
        # safely alias the copy as it might end up mutating
        # a global state, which'd cause semantic breakage.
        continue

      # print pipeline.info.esc.locals
      # debugecho "Optimizing local %" & $copy.source & " -> %" & $copy.dest

      unmutated.incl(copy)

  ensureMove(unmutated)

func rewriteInstructions*(pipeline: var pipeline.Pipeline, unmut: HashSet[Copy]) =
  if unmut.len < 1:
    return

  template substitute(m) =
    # 1984 simulator
    if m.kind == avkPos and m.vreg == unmutCopy.dest:
      m.vreg = unmutCopy.source

  let insts = pipeline.fn.insts
  pipeline.fn.insts.reset()

  # Now, we can rewrite all usages of `dest` with `source` per Copy
  # We can also eliminate the Copy that created the unneeded vreg
  for inst in insts:
    var inst = inst
    var deleted = false
    for unmutCopy in unmut:
      case inst.kind
      of InstKind.Copy:
        if inst.args[1].kind == avkPos and inst.args[1].vreg == unmutCopy.dest:
          deleted = true
      else:
        substitute inst.args[0]
        substitute inst.args[1]

    if deleted:
      continue

    pipeline.fn.insts &= ensureMove(inst)

func propagateCopies*(pipeline: var pipeline.Pipeline) =
  let copies = scanAllCopies(pipeline)
  let unmut = eliminateUnmutatedCopies(pipeline, copies)

  rewriteInstructions(pipeline, unmut)
