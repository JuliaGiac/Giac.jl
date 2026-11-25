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
- **Wrapper version.** The capture needs `libgiac_julia_jll` 0.6 or later.
  With an older wrapper, `evaluate_with_diagnostics` throws a `GiacError`.
