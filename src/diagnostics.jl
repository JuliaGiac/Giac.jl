# Diagnostics capture: GIAC log messages returned apart from the value.
#
# GIAC writes informational messages to the per-context `logptr` stream
# (stderr by default) rather than returning them. The motivating case is a
# definite integral with no closed form: GIAC returns it unevaluated and
# logs a numeric estimate, `// ∫ ~= 0.272198261288`. That estimate is a hint
# whose accuracy is GIAC's choice, not a requested numeric evaluation, so it
# is never turned into the value; `evaluate_with_diagnostics` hands it back
# next to the value instead.
#
# The redirection is done by the wrapper on the C++ context itself
# (libgiac-julia-wrapper `log_capture_begin/end`), so every evaluation path
# is covered, including the `apply_func*` fast paths `invoke_cmd` uses.

"""
    DiagnosticLevel

Severity of a [`GiacDiagnostic`](@ref): `DiagnosticLevel.INFO`,
`DiagnosticLevel.WARNING` or `DiagnosticLevel.ERROR`. The type is
`DiagnosticLevel.T`.
"""
module DiagnosticLevel
    @enum T INFO WARNING ERROR
end

"""
    GiacDiagnostic(level, text, raw)

One line GIAC wrote to its log stream during an evaluation.

# Fields
- `level::DiagnosticLevel.T`: severity, inferred from the text (see below)
- `text::String`: the message, without GIAC's `// ` comment prefix
- `raw::String`: the line exactly as GIAC wrote it

GIAC's log is free-form text, not a structured channel, so `level` is a
heuristic: lines starting with `Warning` are `WARNING`, lines starting with
`Error` are `ERROR`, everything else is `INFO`. Keep `raw` (or the full
[`GiacEvalResult`](@ref) `log`) when the exact output matters.
"""
struct GiacDiagnostic
    level::DiagnosticLevel.T
    text::String
    raw::String
end

"""
    GiacEvalResult{T}

Returned by [`evaluate_with_diagnostics`](@ref).

# Fields
- `value::T`: what the function returned, unchanged
- `diagnostics::Vector{GiacDiagnostic}`: the log, split into one entry per
  non-empty line
- `log::String`: the log text exactly as GIAC wrote it
"""
struct GiacEvalResult{T}
    value::T
    diagnostics::Vector{GiacDiagnostic}
    log::String
end

function Base.show(io::IO, ::MIME"text/plain", r::GiacEvalResult)
    print(io, "GiacEvalResult:\n  value: ")
    show(IOContext(io, :compact => true), r.value)
    if isempty(r.diagnostics)
        print(io, "\n  diagnostics: none")
    else
        print(io, "\n  diagnostics:")
        for d in r.diagnostics
            print(io, "\n    [", d.level, "] ", d.text)
        end
    end
end

# Whether the loaded wrapper has the log capture API (libgiac_julia_jll 0.6+).
function _log_capture_available()::Bool
    return GiacCxxBindings._have_library &&
           isdefined(GiacCxxBindings, :log_capture_begin)
end

function _diagnostic_level(text::AbstractString)::DiagnosticLevel.T
    t = lowercase(text)
    startswith(t, "warning") && return DiagnosticLevel.WARNING
    startswith(t, "error") && return DiagnosticLevel.ERROR
    return DiagnosticLevel.INFO
end

# Split a captured log into one GiacDiagnostic per non-empty line.
function _parse_diagnostics(log::AbstractString)::Vector{GiacDiagnostic}
    diagnostics = GiacDiagnostic[]
    for line in split(log, '\n')
        raw = rstrip(line)
        s = strip(raw)
        isempty(s) && continue
        text = startswith(s, "//") ? lstrip(chop(s; head = 2, tail = 0)) : s
        push!(diagnostics,
              GiacDiagnostic(_diagnostic_level(text), String(text),
                             String(raw)))
    end
    return diagnostics
end

"""
    evaluate_with_diagnostics(f; context=DEFAULT_CONTEXT[]) -> GiacEvalResult

Call `f()` and return its result together with the messages GIAC logged
while it ran. Without the capture, these messages go to stderr.

The value is exactly what `f()` returns; nothing is read back from the log
into it. A definite integral with no closed form stays unevaluated, and the
numeric estimate GIAC prints is available only as a diagnostic.

```julia
using Giac
using Giac.Commands: integrate
@giac_var x
out = evaluate_with_diagnostics() do
    integrate(log(1 + x) / (1 + x^2), x, 0, 1)
end
out.value                  # integrate(ln(1+x)/(1+x^2),x,0,1)
out.diagnostics[1].level   # DiagnosticLevel.INFO
out.diagnostics[1].text    # "∫ ~= 0.272198261288"
```

# Keyword arguments
- `context::GiacContext`: also capture the log of this context, for code
  that evaluates through `giac_eval(expr, ctx)`. The default context is
  always captured. When both produce text, the default context's log comes
  first.

# Notes
- Captures nest: an inner call sees its own messages, and the outer call
  sees them too.
- The GIAC lock is held while `f` runs, so messages from other tasks do not
  end up in the capture. Do not wait inside `f` for another task that
  itself calls GIAC: it would block on the lock.
- The default context is per OS thread. If `f` yields and its task resumes
  on another thread, the capture cannot be closed where it was opened; a
  warning is issued and the default context's log is lost.
- If `f` throws, the log stream is restored and the exception propagates;
  the log is dropped. To keep it, catch inside `f`:
  `evaluate_with_diagnostics(() -> try g() catch e; e end)`.
- Messages GIAC writes straight to stderr/stdout, bypassing its log stream,
  are not captured.
- Requires `libgiac_julia_jll` 0.6 or later; with an older wrapper this
  throws a `GiacError`.
"""
function evaluate_with_diagnostics(f; context::GiacContext = DEFAULT_CONTEXT[])
    if !_log_capture_available()
        throw(GiacError("evaluate_with_diagnostics requires a GIAC wrapper " *
                        "with log capture (libgiac_julia_jll 0.6 or later); " *
                        "the loaded wrapper is " *
                        "$(GiacCxxBindings.wrapper_version())", :eval))
    end
    ctx = _get_context(context.ptr)
    return with_giac_lock() do
        tid = Threads.threadid()
        GiacCxxBindings.log_capture_begin()
        ctx === nothing || GiacCxxBindings.log_capture_begin(ctx)
        log = ""
        value = try
            f()
        finally
            ctx_log = ctx === nothing ? "" :
                      String(GiacCxxBindings.log_capture_end(ctx))
            shared_log = if Threads.threadid() == tid
                String(GiacCxxBindings.log_capture_end())
            else
                @warn "evaluate_with_diagnostics: the task moved to another " *
                      "thread while f ran; the default context's log " *
                      "capture could not be closed and its text is lost."
                ""
            end
            log = shared_log * ctx_log
        end
        GiacEvalResult(value, _parse_diagnostics(log), log)
    end
end
