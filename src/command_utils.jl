# Dynamic command invocation for Giac.jl
# Enables calling any GIAC command via giac_cmd(:cmd, args...)

# ============================================================================
# Argument Conversion
# ============================================================================

"""
    _arg_to_giac_string(arg)

Convert a Julia argument to a GIAC-compatible string representation.

# Supported types
- `GiacExpr`: Uses string representation
- `String`: Used directly (passthrough)
- `Rational`: Converted to GIAC fraction syntax `(num)/(den)` (e.g., `1//2` → `"(1)/(2)"`)
- `Complex`: Converted to GIAC complex syntax `(re)+(im)*i` (e.g., `1+2im` → `"(1)+(2)*i"`)
- `AbstractIrrational`: Mapped to GIAC constants (e.g., `π` → `"pi"`, `ℯ` → `"e"`)
- `Number`: Other numeric types converted via `string()` (Integer, Float, BigInt, etc.)
- `Symbol`: Converted to string (for variable names, e.g., `:x` → `"x"`)
- `AbstractVector`: Converted to GIAC list syntax `[a,b,c]`

# Type Dispatch Order
More specific types (Rational, Complex, AbstractIrrational) are handled before
the general Number fallback, ensuring correct GIAC syntax for each type.

# Examples
```julia
_arg_to_giac_string(giac_eval("x^2"))  # "x^2"
_arg_to_giac_string(1000)               # "1000"
_arg_to_giac_string(1//2)               # "(1)/(2)"
_arg_to_giac_string(1 + 2im)            # "(1)+(2)*i"
_arg_to_giac_string(π)                  # "pi"
_arg_to_giac_string(:x)                 # "x"
_arg_to_giac_string([1, 2, 3])          # "[1,2,3]"
```

# Errors
Throws `ArgumentError` for unsupported types like `Nothing`, `Missing`, or `Dict`.

# See also
- [`GiacInput`](@ref): Union type for valid GIAC input types
- [`invoke_cmd`](@ref): Uses this function for argument conversion
"""
function _arg_to_giac_string(arg::GiacExpr)::String
    return string(arg)
end

function _arg_to_giac_string(arg::String)::String
    return arg
end

# Rational numbers need explicit fraction syntax (022-julia-type-conversion)
# Julia's string(1//2) returns "1//2" but GIAC uses "/" not "//"
function _arg_to_giac_string(arg::Rational)::String
    return "($(numerator(arg)))/($(denominator(arg)))"
end

# Complex numbers need GIAC's imaginary unit syntax (022-julia-type-conversion)
# Julia uses "im" but GIAC uses "i"
function _arg_to_giac_string(arg::Complex)::String
    re, im_part = real(arg), imag(arg)
    return "($(re))+($(im_part))*i"
end

# AbstractIrrational types (pi, e, etc.) need mapping to GIAC symbols (022-julia-type-conversion)
function _arg_to_giac_string(arg::AbstractIrrational)::String
    if arg === π
        return "pi"
    elseif arg === MathConstants.e
        return "e"
    elseif arg === MathConstants.γ  # Euler-Mascheroni constant
        return "euler_gamma"
    elseif arg === MathConstants.catalan
        return "catalan"
    elseif arg === MathConstants.φ  # Golden ratio
        return "(1+sqrt(5))/2"
    else
        # Fallback to numeric approximation for unknown irrationals
        return string(Float64(arg))
    end
end

# AbstractFloat handling for Inf/-Inf (038-inf-support)
# Julia's Inf becomes "Inf" (uppercase) but GIAC expects "inf" (lowercase)
function _arg_to_giac_string(arg::AbstractFloat)::String
    if isinf(arg)
        return arg > 0 ? "inf" : "-inf"
    else
        return string(arg)
    end
end

# General Number fallback (integers, etc.)
function _arg_to_giac_string(arg::Number)::String
    return string(arg)
end

function _arg_to_giac_string(arg::Symbol)::String
    return string(arg)
end

function _arg_to_giac_string(arg::AbstractVector)::String
    elements = [_arg_to_giac_string(x) for x in arg]
    return "[" * join(elements, ",") * "]"
end

# GiacMatrix - convert to GIAC matrix format [[a,b],[c,d]] (058-commands-matrix-support)
function _arg_to_giac_string(arg::GiacMatrix)::String
    rows_str = String[]
    for i in 1:arg.rows
        row_elements = String[]
        for j in 1:arg.cols
            push!(row_elements, string(arg[i, j]))
        end
        push!(rows_str, "[" * join(row_elements, ",") * "]")
    end
    return "[" * join(rows_str, ",") * "]"
end

# DerivativeCondition - unevaluated derivative initial conditions (035-derivative-operator)
function _arg_to_giac_string(arg::DerivativeCondition)::String
    return arg.condition_str
end

# DerivativePoint - derivative at a point (035-derivative-operator)
function _arg_to_giac_string(arg::DerivativePoint)::String
    return string(arg)
end

function _arg_to_giac_string(arg::Function)::String
    string(nameof(arg))
end

function _arg_to_giac_string(arg)
    throw(ArgumentError("Cannot convert $(typeof(arg)) to GIAC string representation"))
end

# ============================================================================
# Command String Building
# ============================================================================

"""
    _build_command_string(cmd::String, args::Vector{String})

Build a GIAC command string from command name and string arguments.

# Example
```julia
_build_command_string("factor", ["x^2-1"])  # Returns "factor(x^2-1)"
_build_command_string("diff", ["x^2", "x"]) # Returns "diff(x^2,x)"
```
"""
function _build_command_string(cmd::String, args::Vector{String})::String
    if isempty(args)
        return "$cmd()"
    end
    return "$cmd(" * join(args, ",") * ")"
end

# ============================================================================
# Core Command Invocation
# ============================================================================

"""
    giac_cmd(cmd::Symbol, args...) -> GiacExpr

Invoke any GIAC command by name and return the result as a GiacExpr.

This is the core function for dynamic command invocation, enabling access to
all 2200+ GIAC commands through a uniform interface.

# Arguments
- `cmd::Symbol`: GIAC command name (e.g., `:factor`, `:sin`, `:integrate`)
- `args...`: Command arguments (GiacExpr, String, Number, or Symbol)

# Returns
- `GiacExpr`: Result of command execution

# Throws
- `GiacError(:eval)`: If command is unknown or execution fails
- `ArgumentError`: If arguments cannot be converted to GIAC format

# Examples
```julia
# Single argument
expr = giac_eval("x^2 - 1")
result = giac_cmd(:factor, expr)  # Returns (x-1)*(x+1)

# Multiple arguments
x = giac_eval("x")
derivative = giac_cmd(:diff, expr, x)  # Returns 2*x

# Trigonometric functions
result = giac_cmd(:sin, giac_eval("pi/6"))  # Returns 1/2
```

# See also
- `giac_eval`: Direct string evaluation
- `search_commands`: Find available commands
- `giac_help`: Get help for a command
"""
function giac_cmd(cmd::Symbol, args...)::GiacExpr
    # Validate command exists (using Symbol directly)
    if !isempty(VALID_COMMANDS) && cmd ∉ VALID_COMMANDS
        # Use suggest_commands from command_registry.jl (005-nearest-command-suggestions)
        suggestions = suggest_commands(cmd)
        suggestion_text = _format_suggestions(suggestions)
        throw(GiacError("Unknown command: $cmd.$suggestion_text", :eval))
    end

    # Warn about Julia conflicts (008-all-giac-commands, FR-010)
    # This helps users understand why certain commands can't be exported directly
    _warn_conflict(cmd)

    # Convert arguments to GIAC strings
    arg_strings = String[]
    for arg in args
        try
            push!(arg_strings, _arg_to_giac_string(arg))
        catch e
            if e isa ArgumentError
                rethrow()
            end
            throw(ArgumentError("Cannot convert argument of type $(typeof(arg)) to GIAC format"))
        end
    end

    # Build and execute command (convert Symbol to String only at C++ boundary)
    cmd_str = string(cmd)
    cmd_string = _build_command_string(cmd_str, arg_strings)

    return with_giac_lock() do
        giac_eval(cmd_string)
    end
end

# ============================================================================
# Base Function Extensions (using Tier 1 wrappers for performance)
# ============================================================================

# Note: These use Tier 1 wrappers when available, falling back to giac_cmd.
# The public API is invoke_cmd from Giac.Commands.

# Helper to wrap Tier 1 unary functions
function _tier1_or_fallback(tier1_func::Function, cmd::Symbol, expr::GiacExpr)::GiacExpr
    result_ptr = tier1_func(expr.ptr)
    if result_ptr != C_NULL
        return GiacExpr(result_ptr)
    end
    # Fall back to string-based command
    return giac_cmd(cmd, expr)
end

# Helper to wrap Tier 1 binary functions
function _tier1_or_fallback_binary(tier1_func::Function, cmd::Symbol, a::GiacExpr, b::GiacExpr)::GiacExpr
    result_ptr = tier1_func(a.ptr, b.ptr)
    if result_ptr != C_NULL
        return GiacExpr(result_ptr)
    end
    # Fall back to string-based command
    return giac_cmd(cmd, a, b)
end

# Helper to wrap Tier 1 ternary functions
function _tier1_or_fallback_ternary(tier1_func::Function, cmd::Symbol, a::GiacExpr, b::GiacExpr, c::GiacExpr)::GiacExpr
    result_ptr = tier1_func(a.ptr, b.ptr, c.ptr)
    if result_ptr != C_NULL
        return GiacExpr(result_ptr)
    end
    # Fall back to string-based command
    return giac_cmd(cmd, a, b, c)
end

"""
    Base.sin(expr::GiacExpr) -> GiacExpr

Compute the sine of a GiacExpr. Enables natural Julia syntax for symbolic math.
Uses Tier 1 C++ wrapper for high performance.

# Example
```julia
x = giac_eval("x")
result = sin(x^2)  # Works naturally with GiacExpr
```
"""
Base.sin(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_sin_tier1, :sin, expr)
Base.sind(expr::GiacExpr)::GiacExpr = sin(deg2rad(expr))
Base.sinpi(expr::GiacExpr)::GiacExpr = sin(π * expr)

"""
    Base.cos(expr::GiacExpr) -> GiacExpr

Compute the cosine of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.cos(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_cos_tier1, :cos, expr)
Base.cosd(expr::GiacExpr)::GiacExpr = cos(deg2rad(expr))
Base.cospi(expr::GiacExpr)::GiacExpr = cos(π * expr)

"""
    Base.tan(expr::GiacExpr) -> GiacExpr

Compute the tangent of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.tan(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_tan_tier1, :tan, expr)
Base.tand(expr::GiacExpr)::GiacExpr = tan(deg2rad(expr))
Base.tanpi(expr::GiacExpr)::GiacExpr = tan(π * expr)

"""
    Base.asin(expr::GiacExpr) -> GiacExpr

Compute the arc sine of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.asin(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_asin_tier1, :asin, expr)
# Inverse-degree trig: takes a value in [-1, 1] (or [0, ...) for atan), returns
# the angle in degrees. Mirrors Julia Base: asind(x) = rad2deg(asin(x)).
Base.asind(expr::GiacExpr)::GiacExpr = rad2deg(asin(expr))

"""
    Base.acos(expr::GiacExpr) -> GiacExpr

Compute the arc cosine of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.acos(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_acos_tier1, :acos, expr)
Base.acosd(expr::GiacExpr)::GiacExpr = rad2deg(acos(expr))

"""
    Base.atan(expr::GiacExpr) -> GiacExpr

Compute the arc tangent of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.atan(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_atan_tier1, :atan, expr)
Base.atand(expr::GiacExpr)::GiacExpr = rad2deg(atan(expr))

Base.secd(expr::GiacExpr)::GiacExpr = sec(deg2rad(expr))
Base.cscd(expr::GiacExpr)::GiacExpr = csc(deg2rad(expr))
Base.cotd(expr::GiacExpr)::GiacExpr = cot(deg2rad(expr))

Base.asecd(expr::GiacExpr)::GiacExpr = rad2deg(asec(expr))
Base.acscd(expr::GiacExpr)::GiacExpr = rad2deg(acsc(expr))
Base.acotd(expr::GiacExpr)::GiacExpr = rad2deg(acot(expr))

Base.sincos(expr::GiacExpr)::Tuple{GiacExpr, GiacExpr} = (sin(expr), cos(expr))
Base.sincosd(expr::GiacExpr)::Tuple{GiacExpr, GiacExpr} = (sind(expr), cosd(expr))
Base.sincospi(expr::GiacExpr)::Tuple{GiacExpr, GiacExpr} = (sinpi(expr), cospi(expr))

Base.deg2rad(expr::GiacExpr)::GiacExpr = (expr*pi) / 180
Base.rad2deg(expr::GiacExpr)::GiacExpr = (expr*180) / pi

"""
    Base.exp(expr::GiacExpr) -> GiacExpr

Compute the exponential of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.exp(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_exp_tier1, :exp, expr)
Base.exp2(expr::GiacExpr)::GiacExpr = 2^expr
Base.exp10(expr::GiacExpr)::GiacExpr = 10^expr

"""
    Base.log(expr::GiacExpr) -> GiacExpr

Compute the natural logarithm of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.log(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_ln_tier1, :ln, expr)
Base.log1p(expr::GiacExpr)::GiacExpr = log(1 + expr)
Base.log(b::GiacExpr, x::GiacExpr)::GiacExpr = log(x) / log(b)
Base.log(b::Number, x::GiacExpr)::GiacExpr = log(promote(b, x)...)


"""
    Base.sqrt(expr::GiacExpr) -> GiacExpr

Compute the square root of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.sqrt(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_sqrt_tier1, :sqrt, expr)

"""
    Base.cbrt(expr::GiacExpr) -> GiacExpr

Compute the cube root of a GiacExpr.
"""
Base.cbrt(expr::GiacExpr)::GiacExpr = Commands.surd(expr, 3)

"""
    Base.abs(expr::GiacExpr) -> GiacExpr

Compute the absolute value of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.abs(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_abs_tier1, :abs, expr)

"""
    Base.sign(expr::GiacExpr) -> GiacExpr

Compute the sign of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.sign(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_sign_tier1, :sign, expr)

"""
    Base.floor(expr::GiacExpr) -> GiacExpr

Compute the floor of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.floor(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_floor_tier1, :floor, expr)

"""
    Base.ceil(expr::GiacExpr) -> GiacExpr

Compute the ceiling of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.ceil(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_ceil_tier1, :ceil, expr)

"""
    Base.real(expr::GiacExpr) -> GiacExpr

Extract the real part of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.real(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_re_tier1, :re, expr)

"""
    Base.imag(expr::GiacExpr) -> GiacExpr

Extract the imaginary part of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.imag(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_im_tier1, :im, expr)

"""
    Base.conj(expr::GiacExpr) -> GiacExpr

Compute the complex conjugate of a GiacExpr.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.conj(expr::GiacExpr)::GiacExpr = _tier1_or_fallback(_giac_conj_tier1, :conj, expr)
Base.adjoint(expr::GiacExpr)::GiacExpr = conj(expr)

"""
    Base.isfinite(expr::GiacExpr) -> Bool

Return `true` when `expr` is not infinite. Mirrors Julia's convention for
numeric types: equivalent to `!isinf(expr)`, with the GIAC-side `isinf`
result converted to a Julia `Bool` via [`to_julia`](@ref). Identifiers and
ordinary symbolic expressions are reported as finite (they are not
recognized as `inf`).

# Examples
```julia
isfinite(giac_eval("1"))      # true
isfinite(giac_eval("inf"))    # false
isfinite(giac_eval("-inf"))   # false
isfinite(giac_eval("1/0"))    # false  (GIAC normalizes 1/0 to inf)
isfinite(giac_eval("x"))      # true   (a free variable is finite)
```
"""
Base.isfinite(expr::GiacExpr)::Bool = !to_julia(isinf(expr))::Bool

"""
    Base.gcd(a::GiacExpr, b::GiacExpr) -> GiacExpr

Compute the greatest common divisor of two GiacExprs.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.gcd(a::GiacExpr, b::GiacExpr)::GiacExpr = _tier1_or_fallback_binary(_giac_gcd_tier1, :gcd, a, b)

"""
    Base.lcm(a::GiacExpr, b::GiacExpr) -> GiacExpr

Compute the least common multiple of two GiacExprs.
Uses Tier 1 C++ wrapper for high performance.
"""
Base.lcm(a::GiacExpr, b::GiacExpr)::GiacExpr = _tier1_or_fallback_binary(_giac_lcm_tier1, :lcm, a, b)

"""
    Base.collect(expr::GiacExpr) -> GiacExpr

Collect like terms in a polynomial expression using GIAC's `collect` command.

Overrides `Base.collect` for `GiacExpr` so that `collect(expr)` calls GIAC's
symbolic `collect` rather than Julia's iteration-based `collect`.

# Examples
```julia
@giac_var x
collect(x^2 - 4x + 4)  # Returns (x-2)^2
```
"""
Base.collect(expr::GiacExpr)::GiacExpr = giac_cmd(:collect, expr)


Base.zero(::GiacExpr)::GiacExpr = giac_eval("0")
Base.zero(::Type{GiacExpr})::GiacExpr = giac_eval("0")
Base.one(::GiacExpr)::GiacExpr = giac_eval("1")
Base.one(::Type{GiacExpr})::GiacExpr = giac_eval("1")

# ============================================================================
# Base Math Fallbacks (Issue #71)
# ============================================================================

for (fname, expr) in [
    (:abs2,  :(abs(x)^2)),
    (:cis,   :(exp(Constants._i[] * x))),
    (:cispi, :(exp(Constants._i[] * pi * x))),
    (:expm1, :(exp(x) - 1)),
    (:sech,  :(1 / cosh(x))),
    (:csch,  :(1 / sinh(x))),
    (:coth,  :(1 / tanh(x))),
    (:asech, :(acosh(1 / x))),
    (:acsch, :(asinh(1 / x))),
    (:acoth, :(atanh(1 / x))),
    (:sinc,  :(sin(pi * x) / (pi * x))),
    (:mod2pi,:(x - 2 * pi * floor(x / (2 * pi)))),
]
    @eval Base.$fname(x::GiacExpr)::GiacExpr = $expr
end

if isdefined(Base, :fourthroot)
    Base.fourthroot(x::GiacExpr)::GiacExpr = Commands.surd(x, 4)
end

Base.hypot(x::GiacExpr, y::GiacExpr)::GiacExpr = sqrt(abs2(x) + abs2(y))
Base.hypot(x::GiacExpr, y::Number)::GiacExpr = hypot(promote(x, y)...)
Base.hypot(x::Number, y::GiacExpr)::GiacExpr = hypot(promote(x, y)...)

Base.clamp(x::GiacExpr, lo, hi)::GiacExpr = Commands.min(Commands.max(x, lo), hi)
