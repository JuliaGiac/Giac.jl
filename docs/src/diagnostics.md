# Capturing GIAC messages

Some GIAC commands report information without putting it in their result.
They write it to GIAC's log stream instead, which ends up on stderr. The
best-known case is a definite integral GIAC cannot evaluate in closed form,
for example Serret's integral:

```julia
using Giac
using Giac.Commands: integrate
@giac_var x

integrate(log(1 + x) / (1 + x^2), x, 0, 1)
# stderr: // ∫ ~= 0.272198261288
# result: integrate(ln(1+x)/(1+x^2),x,0,1)
```

The result is the unevaluated integral. The numeric estimate appears only as
a side message, which a program cannot read.

## `evaluate_with_diagnostics`

[`evaluate_with_diagnostics`](@ref) runs a function and returns its result
together with what GIAC logged in the meantime:

```julia
out = evaluate_with_diagnostics() do
    integrate(log(1 + x) / (1 + x^2), x, 0, 1)
end

out.value                  # integrate(ln(1+x)/(1+x^2),x,0,1)  (a GiacExpr)
out.diagnostics[1].level   # DiagnosticLevel.INFO
out.diagnostics[1].text    # "∫ ~= 0.272198261288"
out.diagnostics[1].raw     # "// ∫ ~= 0.272198261288"
out.log                    # the raw log text, "// ∫ ~= 0.272198261288\n"
```

While the capture is active, these log messages no longer go to stderr.

### The value is never changed

`out.value` is exactly what the function returned. Here it is the same
`GiacExpr` as a plain `integrate(...)` call, and `integrate` itself still
returns a `GiacExpr`. The estimate is GIAC's numerical hint, computed with a
precision and tolerance that GIAC chooses. It is not the result of a numeric
evaluation you requested, so Giac.jl never puts it in place of the value.
For a controlled numeric value, ask for one explicitly, for example with
`evalf` or approximate bounds.

### Diagnostics

The log is split into one [`GiacDiagnostic`](@ref) per non-empty line:

| field   | content |
|---------|---------|
| `level` | a [`DiagnosticLevel`](@ref): `INFO`, `WARNING` or `ERROR` |
| `text`  | the message without GIAC's `// ` comment prefix |
| `raw`   | the line exactly as GIAC wrote it |

GIAC's log is free-form text, not a structured channel, so the level is a
heuristic. Lines starting with `Warning` are `WARNING`, lines starting with
`Error` are `ERROR`, and everything else is `INFO`. The wording of these
messages can change between GIAC versions; match on `raw` or `log` with care.

## What a message says: `kind`

Each diagnostic has a `kind`, classified against the messages GIAC is known to
write, so that a caller need not match the text:

| `kind` | GIAC's message (example) | The value is right… |
|---|---|---|
| `:estimate` | `∫ ~= 0.272198261288` | (an estimate of a value GIAC left unevaluated) |
| `:assumption` | `integration of abs or sign assumes constant sign by intervals`, then `Check [abs(x-1)]` | only under what is assumed |
| `:choice` | `choosing root of [...] at parameters values [0]`, `need to choose a branch` | only for the choice made |
| `:unchecked` | `No checks were made for singular points of antiderivative …` | if the unchecked step holds |
| `:interpretation` | `argument is not an equation, solving x^3+a*x+b=0` | for the input as GIAC read it |
| `:info`, `:warning`, `:error` | anything else, by level | |

`:assumption`, `:choice` and `:unchecked` qualify the value: a caller certifying a
result should treat them as open conditions. An `:estimate` is evidence only.

```julia
out = evaluate_with_diagnostics(() -> integrate(abs(x - 1), x, 0, 3))
[d.kind for d in out.diagnostics]    # [:estimate, :assumption, :assumption]
```

## What is covered

The capture is installed on the GIAC context itself, inside the C++ wrapper,
not around individual functions. Every evaluation path that uses the context
is therefore covered: `giac_eval`, the `invoke_cmd` fast path that
`Giac.Commands.integrate` and the other commands go through, operators and
conversions.

If your code evaluates in a dedicated [`GiacContext`](@ref), pass it so that
its log is captured as well:

```julia
ctx = GiacContext()
out = evaluate_with_diagnostics(context = ctx) do
    giac_eval("integrate(ln(1+x)/(1+x^2),x,0,1)", ctx)
end
```

## Through the extensions

The capture holds for every extension: what an extension evaluates goes
through GIAC's context like the rest, so wrapping the conversion and the
computation keeps the value, in the extension's own type, and GIAC's messages:

```julia
using Giac, Symbolics
@variables x
out = evaluate_with_diagnostics() do
    to_symbolics(Giac.Commands.integrate(to_giac(abs(x)), giac_eval("x")))
end
out.value          # a Symbolics expression: x^2/2 times sign(x)
out.diagnostics    # :assumption, "integration of abs or sign assumes constant sign by intervals…"
```

| Extension | Wrap in `evaluate_with_diagnostics` |
|---|---|
| Symbolics, SymbolicUtils, SymPy, MathJSON | `to_giac`, the computation, and the conversion back |
| OpenMath.jl | `Giac.from_openmath(o)`, which GIAC evaluates |
| TermInterface, Nemo, LibPARI, BlockArrays | the computation that uses the converted values |
| MCP server | nothing: the `giac_eval` tool returns the result, then a `GIAC messages:` block, also with an error |

An exception leaves `evaluate_with_diagnostics` without a result; to keep the
messages GIAC wrote before it, catch it inside the block:

```julia
out = evaluate_with_diagnostics() do
    try
        giac_eval("integrate(abs(t),t)")
        giac_eval("inv([[1,2],[2,4]])")      # not invertible: an error
    catch e
        e
    end
end
out.value          # the exception
out.diagnostics    # what GIAC said about the integral before
```

GIAC's log is not always valid UTF-8 (some builds write Latin-1, and a syntax
error used to quote freed memory): such bytes are read as Latin-1, so
`text`, `raw` and `log` are always valid strings.

## Behaviour and limits

- **Nesting.** Calls can be nested. An inner call returns its own messages,
  and the enclosing call sees them too.
- **Exceptions.** If the function throws, the log stream is restored and the
  exception propagates without the log. To keep the log, catch inside:
  `evaluate_with_diagnostics(() -> try g() catch e; e end)`.
- **Locking.** The GIAC lock is held while the function runs, so messages
  from other tasks cannot leak into the capture. Do not wait inside the
  function for another task that calls GIAC: it would block on that lock.
- **Threads.** The default GIAC context is per OS thread. If the function
  yields and its task resumes on another thread, the capture cannot be
  closed where it was opened. A warning is issued and that log is lost.
- **Direct writes.** Messages that GIAC writes straight to stderr or stdout,
  bypassing its log stream, are not captured.
- **Wrapper version.** With `libgiac_julia_jll` 0.6 or later, the wrapper
  captures GIAC's log stream on the C++ context. With an older wrapper, stderr
  is redirected to a temporary file instead, which catches GIAC's log stream
  as long as it writes to stderr, its default. Then anything else written to
  stderr while the function runs (a Julia warning, for instance) is captured
  too, and the `context` keyword adds nothing, as every context writes to the
  same stderr.
