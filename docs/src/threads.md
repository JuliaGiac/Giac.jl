# Threads and global state

Giac.jl can be called from several tasks and threads at once. This page states
what that guarantees, and what is shared.

## What is safe

- **Every call into GIAC is serialized** by one process-wide lock
  (`Giac.GIAC_LOCK`, taken by `with_giac_lock`). Concurrent calls wait for one
  another, so they are memory-safe, but GIAC work itself does not run in
  parallel.
- **A `GiacExpr` is a value**: it can be created on one thread and used on
  another. Finalizers never free GIAC objects themselves; they queue them, and
  the next lock holder frees them.
- **The package extensions** (Symbolics, MathJSON, Nemo, SymPy, LibPARI,
  TermInterface, MCP) take the same lock around their calls into GIAC. The
  SymPy bridge never holds it while it calls Python.

## What is shared

GIAC keeps its state in a *context*: the values given with `:=`, the
assumptions made with `assume` or `@giac_var x::positive`, and the settings
(`complex_mode`, `epsilon`, `Digits`, …). That state is global to the context:
an assumption made by one task holds for every other task using the same
context.

- **An explicit context** (`ctx = GiacContext()`, passed as
  `giac_eval(s, ctx)`) is shared by every thread that uses it.
- **The default context** is shared by the tasks of one OS thread. With
  libgiac_julia_jll 0.6 and later (libgiac-julia-wrapper #18), it is one
  context for the whole process. Before that, each OS thread had its own, so a
  variable assigned on one thread was not seen on another: pass an explicit
  context to share state across threads.

## Scoping global state

`assuming(f, conditions...)` and `with_settings(f; …)` change the global
state for one block and put it back afterwards, even when the block throws.
They hold the GIAC lock for the whole block, so no other task sees the
temporary assumptions or settings, and other tasks wait until the block ends:

```julia
@giac_var k
assuming(k > 0) do
    Giac.Commands.simplify(sqrt(k^2))      # k, on this task only
end
with_settings(complex_mode = false) do
    Giac.Commands.simplify(sqrt(k^2))      # abs(k)
end
```

Report `giac_settings()` and `giac_version()` next to a result to say what it
was computed with.

See [Memory Management](developer/memory.md#Thread-Safety) for how the lock
and the freeing of objects work.
