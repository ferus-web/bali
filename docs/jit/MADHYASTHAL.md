# Madhyasthal
Bali has had a baseline JIT compiler since 0.7.0 - known as the baseline compiler. It translates the VM's bytecode structures directly into native x86-64 code. \
It is very fast, but its code generation quality is very bad. It does not perform any optimizations on the clause given to it.

Keeping this in mind, Madhyasthal (literally meaning "middle place" in Hindi) was created. As the name might suggest, it aims to be the middle-point between the baseline JIT and any future higher-tier compilers that may be implemented. It generates much better code than the baseline, at the cost of taking slightly longer to generate the code.

# Function Compilation Eligibility
A function becomes eligible to be compiled by this tier when the `getCompilationJudgement()` returns its judgement as `CompilationJudgement.WarmingUp`. This occurs when:

- 50,000 bytecode instruction dispatches have occurred
- The aforementioned function has been responsible for over 35% of said dispatches.

# Design
## Intermediate Representation
Madhyasthal uses its own IR that is sometimes called MIR (not to be confused with Mirage IR).
It is a two-address-code IR that is fully in-memory by design, in contrast to the bytecode which originally was very wasteful.

## Lowering
Madhyasthal's lowering mechanism works by condensing certain multi-op bytecode patterns into singular operations when possible.
These pattern matching routines can be found at `src/bali/runtime/compiler/amd64/madhyasthal/lowering.nim`.

When such patterns cannot be matched, it emits the MIR-equivalent of the bytecode instruction, which is generally fairly close to the bytecode's op name.

## Optimizations
Currently, Madhyasthal supports a single optimization: a naive dead-code-elimination pass. More optimizations will gradually be added to it.
Madhyasthal uses a pipeline system to let the runtime efficiently choose which optimizations should be enabled, and which shouldn't.

## Code Generation
After the pipeline optimizes the IR, it is then sent off to the midtier JIT's actual compiler: the mechanism that converts MIR to x86-64 code.
This works fairly similarly to how the baseline JIT emits x86-64 code, the only difference being that the midtier compiler works on Madhyasthal's IR, not the VM's bytecode structures.
