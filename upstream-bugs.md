# Bugs in packages Giac.jl depends on

Bugs found while developing Giac.jl in the packages it uses, with where they
stand. Bugs in Giac itself (the C++ library) are handled in the JuliaGiac fork.

## LibPARI.jl ≤ 0.18: a `Gen` finalizer switches tasks

**Seen:** 2026-11-27, in `test/test_extensions_threads.jl`, which forces
`GC.gc()` while LibPARI objects are alive. Julia logs, repeatedly:

```
error in running finalizer: ErrorException("task switch not allowed from inside gc finalizer")
…
put! at ./channels.jl:397
_enqueue_on_primary at LibPARI/src/concurrency.jl:242
_finalize! at LibPARI/src/gen.jl:101
```

`_finalize!` queued the clone to free with `put!` on a `Channel`, which may
block and switch tasks, which a finalizer must not do. The clone is then not
freed (a leak), and the run is noisy; the tests still pass.

**Status:** fixed in LibPARI 0.19.0 (commit f59a9f3, "fix: do not switch tasks
in Gen finalizers": the finalizer now only defers the free). Giac.jl still
resolves LibPARI 0.18.2, because LibPARI 0.19 needs PARI 2.19
(PARI_jll ~200.1900) and GIAC_jll 2.0.3 is built on PARI 2.17. The fix
reaches Giac.jl with GIAC_jll 200.100.0 (GIAC 2.1.0 on PARI 2.19); a
LibPARI 0.18.3 with the fix backported would reach it sooner.
