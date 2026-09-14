# Security Policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub's advisory form](https://github.com/JuliaGiac/Giac.jl/security/advisories/new)
rather than in a public issue.

## The shape of the risk

`giac_eval` hands a string to Giac's evaluation engine:

```
giac_eval(str)  →  GiacContext::eval(str)  →  giac::eval(giac::gen(str, ctx), ctx)
```

Giac is not an expression calculator. It is a programming language with file
access and network access, and there is no sanitizing layer between your string
and it. Anything valid in Giac runs with the privileges of the Julia process.

**Do not pass untrusted input to `giac_eval` without OS-level sandboxing.**

## What Giac blocks on its own

Giac has a global `secure_run` flag, `true` by default on every standard build
(it is disabled only on TI Nspire calculators). Functions guarded by
`check_secure()` refuse to run. Verified against the `GIAC_jll` this package
requires:

| Call | Linux / macOS | Windows |
|---|---|---|
| `cd(path)` | raises, `Running in secure mode` | same |
| `write(path, 0)` | raises, `Running in secure mode` | same |
| `fopen(path)` | raises, `Running in secure mode` | same |
| `archive(path, 1)` | raises, `Running in secure mode` | same |
| `open(path)` | raises, `Running in secure mode` | **does not report secure mode** |

Each raises a `GiacError` carrying that message, and no file is created.

`open` is the exception, and the difference was found by CI rather than
assumed: on Windows it does not report secure mode. What holds on every
platform is that no file appears, which is the property
`test/test_security.jl` asserts everywhere; the message is asserted only where
it holds. If you rely on `open` being refused, do not rely on the message.

The suite checks this on every run, so a build with `secure_run` disabled —
compiled with `-DNSPIRE` — fails rather than shipping quietly.

`system()` is not exposed either. On standard Linux, macOS and Windows builds
it is not defined as a Giac command at all — `system("id")` evaluates to the
inert expression `system("id")`, it does not execute anything.

## What Giac does not block

**The `read*` family is not guarded by `check_secure()`.** It reaches any file
the process can read. `read16` is the clean primitive — it returns the bytes:

```julia
write("/tmp/probe", "SECRET42")
giac_eval("read16(\"/tmp/probe\")")
# [[0,"SECRET42",83,69,67,82,69,84,52,50]]
```

`read` itself is subtler and worth stating precisely, because it is easy to
describe wrongly: it reads the file **and evaluates it as Giac source**. So it
is not a clean exfiltration channel — but it does open any readable file, and
it executes what it finds. `read32`, `readwav` and `readrgb` take the same
unguarded path and differ only in the format they expect.

Giac's `_read` also fetches URLs when the argument starts with `http`, making
it a server-side request forgery vector as well. This package's tests do not
exercise that path — a test suite should not make outbound requests — so treat
it as reported rather than verified here.

This is an upstream gap. The fix is two lines in `_read`, matching what
`write`, `open` and `fopen` already do, and belongs in Giac rather than here.

A Julia-side regex filter on `read` is **not** a substitute. Giac is a
programming language, and a blocklist on the spelling of a call is bypassed by
string construction, aliasing, or indirection. Treat such a filter as defence
in depth if you want it, never as a boundary.

## Denial of service

There is no built-in bound on CPU or memory. `giac_eval("seq(x, x, 1, 10^15)")`
will try.

Giac has a timeout, set with `giac_eval("caseval(\"timeout 5\")")`, and it does
abort a runaway computation — a loop that would run for minutes raises after
about 1.7 s with a one-second limit.

**But it is not usable as an in-process mitigation.** Once it fires, the
interrupt state is process-wide and sticky: every later evaluation raises
`Stopped by user interruption or stack overflow`, and nothing recovers it —
not `restart`, not `caseval`, not even a freshly created `GiacContext`. The
Giac session is finished.

That is why this package does not wrap the timeout in a convenience function:
an API whose success leaves the library unusable is a trap. The timeout is
worth setting only where you can discard the process afterwards — one
evaluation per worker — which is close to what sandboxing gives you anyway.

## Choosing a deployment

| Deployment | Risk | Why |
|---|---|---|
| Local use — you type the expressions | Low | You already have a shell |
| Shared notebook | Medium | A notebook you did not write can read your files |
| Web service taking user input | **High** | Arbitrary file read, HTTP fetch, DoS |
| Teaching platform with student input | **High** | Same, at scale |

For the last two, application-level filtering is not enough. Run Giac in a
sandbox that denies filesystem and network access — `bubblewrap`, `seccomp`, or
a container. This is what SageMath and GeoGebra do when they expose Giac to end
users.

## Version support

Security fixes land on the latest released version. The package requires
`GIAC_jll` 2.0.3 and `libgiac_julia_jll` 0.5.2 or later; earlier pairs carry a
Windows ABI defect that silently truncated MPFR values, and are excluded by
`[compat]`.
