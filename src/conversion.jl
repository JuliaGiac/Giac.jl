# Type conversion for Giac.jl
# Provides extended to_julia functionality with vector/complex/fraction support
#
# Part of feature 029-output-handling, 030-to-julia-bool-conversion
# Updated for 041-scoped-type-enum: Uses GenTypes.T enum instead of GIAC_* constants

using .GenTypes: T, INT, DOUBLE, ZINT, REAL, CPLX, VECT, SYMB, IDNT, FRAC, STRNG, FUNC

# ============================================================================
# Extended to_julia Conversion
# ============================================================================

"""
    to_julia(g::GiacExpr) -> Union{Bool, Int64, BigInt, Float64, Rational, Complex, Vector, String, GiacExpr}

Recursively convert a GIAC expression to native Julia types.

# Conversion Rules
| GIAC Type | Julia Return Type |
|-----------|-------------------|
| Boolean (`true`/`false`) | `Bool` |
| `INT` | `Int64` |
| `ZINT` | `BigInt` |
| `DOUBLE`, `REAL` | `Float64` |
| `FRAC` | `Rational{Int64}` or `Rational{BigInt}` |
| `CPLX` | `Complex{T}` (T promoted from parts) |
| `VECT` | `Vector{T}` (T narrowed from elements) |
| `STRNG` | `String` (the characters, without GIAC's quotes) |
| `SYMB`, `IDNT`, `FUNC` (with no free variables) | numeric value via `evalf` |
| `SYMB`, `IDNT`, `FUNC` (with at least one free variable) | `GiacExpr` (unchanged) |

When a symbolic expression has no free variables (i.e. [`is_constant`](@ref)
returns `true`), `to_julia` calls `Giac.Commands.evalf` to reduce it to a
numeric value and then recurses, so `to_julia(substitute(sin(x), x => 2))`
returns a `Float64`, not `GiacExpr: sin(2)`. The layered design — `evalf(...)`
keeps you in Giac, `to_julia(...)` bridges to Julia — is preserved.

Note: GIAC represents booleans as integers internally, but `to_julia` detects them
via their string representation ("true"/"false") and returns Julia `Bool` values.

# Examples
```jldoctest
julia> to_julia(giac_eval("42"))
42

julia> to_julia(giac_eval("3/4"))
3//4

julia> to_julia(giac_eval("[1,2,3]"))
3-element Vector{Int64}:
 1
 2
 3

julia> to_julia(giac_eval("true"))
true

julia> to_julia(giac_eval("\\"hello\\""))
"hello"
```

# See also
[`giac_type`](@ref), [`is_boolean`](@ref), [`is_numeric`](@ref), [`is_vector`](@ref),
[`is_constant`](@ref), [`unwrap_const`](@ref)
"""
function to_julia(g::GiacExpr)
    if g.ptr == C_NULL
        throw(GiacError("Cannot convert null expression", :type))
    end

    t = giac_type(g)
    return _convert_by_type(g, t)
end

# Internal dispatcher based on type constant
function _convert_by_type(g::GiacExpr, t::T)
    if t == INT
        # Check for boolean before integer conversion (030-to-julia-bool-conversion)
        if is_boolean(g)
            return _convert_to_bool(g)
        end
        return _convert_to_int64(g)
    elseif t == DOUBLE || t == REAL
        return _convert_to_float64(g)
    elseif t == ZINT
        return _convert_to_bigint(g)
    elseif t == FRAC
        return _convert_to_rational(g)
    elseif t == CPLX
        return _convert_to_complex(g)
    elseif t == VECT
        return _convert_to_vector(g)
    elseif t == STRNG
        return _convert_to_string(g)
    else
        # Symbolic types (SYMB, IDNT, FUNC). If the expression has no free
        # variables, reduce it numerically through evalf and recurse — this
        # is what callers asking "give me a Julia value" almost always want
        # (Issue #3). Otherwise return the GiacExpr unchanged.
        if is_constant(g)
            # 18 digits, not `evalf`'s default. With no argument Giac reduces
            # to a DOUBLE and prints it at the global `Digits` — 12 — so every
            # constant reached Julia with four digits missing and
            # `to_julia(giac_eval("pi"))` disagreed with `float` on the same
            # expression. Past 15 digits Giac builds a REAL instead, whose
            # decimal is faithful; 18 covers a Float64, which needs 17 to
            # round-trip and one more to survive the double rounding.
            ev = Commands.evalf(g, 18)
            # GIAC's `infinity` and `undef` atoms are constant-by-no-free-
            # symbols but cannot be reduced numerically: `evalf` is a no-op
            # on them (see issue #19). Detect the fixed point cheaply by
            # pointer identity first, then fall back to string comparison
            # for equivalent expressions that do not share the same pointer,
            # and return the GiacExpr unchanged to avoid infinite recursion.
            ev.ptr == g.ptr && return g
            string(ev) == string(g) && return g
            return to_julia(ev)
        end
        return g
    end
end

"""
    unwrap_const(ex::GiacExpr) -> Number

Unwraps a symbolic expression and returns a number when the expression has no symbolic variables.


"""
function unwrap_const(ex::GiacExpr)
    out = to_julia(ex)
    isa(out, Number) && return out
    if is_constant(ex)
        return to_julia(Commands.evalf(ex))
    end
    return ex
end

# Narrowest BigFloat width that holds `d` significant decimal digits.
_float_width(d::Integer) = max(2, ceil(Int, d * log2(10)))

"""
    AbstractFloat(ex::GiacExpr)
    float(ex::GiacExpr)

Convert a Giac number, constant or array to a floating point value.

Only the constructor is defined. `Base.float(x) = AbstractFloat(x)` is
declared on `Any` rather than on `Number` (`base/float.jl`), so `float` comes
along for free even though `GiacExpr` is not a `Number` — and, unlike a bare
`float` method, this also serves code that reaches for the constructor.

Integers and hardware floats land on `Float64`; a big integer or an MPFR
`REAL` lands on `BigFloat`. A `REAL` keeps the precision its own decimal
carries rather than being rounded to the ambient `precision(BigFloat)`.
Giac's non-finite atoms map to `Inf`, `-Inf` and `NaN`. Anything with a free
symbol, and anything that is not a number at all, raises `ArgumentError`.

# Examples
```jldoctest
julia> using Giac

julia> float(giac_eval("2"))
2.0

julia> float(giac_eval("2.34"))
2.34

julia> float(giac_eval("2 + 3i"))
2.0 + 3.0im

julia> float(giac_eval("1234567890/2345678901"))
0.526315809667591

julia> float(giac_eval("sin(2)")) === sin(2.0)
true

julia> float(giac_eval("[1,2,3]"))
3-element Vector{Float64}:
 1.0
 2.0
 3.0

julia> float(giac_eval("inf")), float(giac_eval("-inf"))
(Inf, -Inf)

julia> float(Giac.Commands.evalf(giac_eval("pi"), 100))
3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706807
```

A big integer widens to `BigFloat`:

```jldoctest; filter = r"e[+]?"
julia> using Giac

julia> float(giac_eval("23456789012345678901"))
2.3456789012345678901e+19
```
"""
function Base.AbstractFloat(ex::GiacExpr)
    T = giac_type(ex)

    T in (INT, DOUBLE, FLOAT) && return convert(Float64, _convert_by_type(ex, T))
    T == ZINT && return convert(BigFloat, _convert_by_type(ex, T))
    if T == REAL
        # Giac prints a REAL at the value's own precision, so the decimal is
        # faithful; parsing it at the ambient width would throw away whatever
        # Giac computed beyond it. Take the width the decimal implies.
        str = string(ex)
        digits = count(isdigit, first(split(str, r"[eE]")))
        return setprecision(() -> parse(BigFloat, str), BigFloat, _float_width(digits))
    end
    T == CPLX && return Complex(AbstractFloat(real(ex)), AbstractFloat(imag(ex)))
    T == FRAC && return AbstractFloat(numer(ex)) / AbstractFloat(denom(ex))
    if T == VECT
        vals = [AbstractFloat(x) for x in ex]
        # An empty comprehension is `Vector{Any}`; narrow it.
        return isempty(vals) ? Float64[] : identity.(vals)
    end

    # Giac's non-finite atoms have no free symbols, so `is_constant` calls
    # them constant, but `evalf` is a no-op on them (issue #19). Without this
    # they reach the numeric branch below and come back unconverted.
    str = string(ex)
    (str == "infinity" || str == "+infinity") && return Inf
    str == "-infinity" && return -Inf
    str == "undef" && return NaN

    if Constants.is_giac_constant(ex)
        ex == Constants._pi[] && return float(pi)
        ex == Constants._e[] && return float(ℯ)
        ex == Constants._i[] && return float(im)
        # Any other recognised constant falls through rather than returning
        # `nothing` from a spent `&&` chain.
    end

    # 18 digits, not 16: a Float64 needs 17 to round-trip, and rounding the
    # exact value to 17 first still costs an ulp on values such as sqrt(2).
    # STRNG is excluded — a Giac string is constant, and is not a number.
    if T != STRNG && is_constant(ex)
        value = to_julia(Commands.evalf(ex, 18))
        value isa Number && return float(value)
    end

    throw(ArgumentError("cannot convert `$str` to a floating point type"))
end

"""
    Float64(ex::GiacExpr)
    BigFloat(ex::GiacExpr)
    convert(T, ex::GiacExpr)

Narrow a Giac value to a concrete floating point type.

Each goes through [`AbstractFloat`](@ref), so they accept exactly what it
accepts — symbolic constants, `sqrt(2)` and the non-finite atoms included.
A value that is not a single real number, such as a complex or a vector,
raises `InexactError`: it has no `Float64`, and silently taking a part of it
would be worse than refusing.
"""
function _real_value(::Type{T}, ex::GiacExpr) where {T<:AbstractFloat}
    value = AbstractFloat(ex)
    value isa Real || throw(InexactError(nameof(T), T, ex))
    return value
end

(::Type{T})(ex::GiacExpr) where {T<:AbstractFloat} = T(_real_value(T, ex))

# `precision` is the point of a `BigFloat`, so take the keyword Base takes.
Base.BigFloat(ex::GiacExpr; precision::Integer = Base.MPFR.DEFAULT_PRECISION[]) =
    BigFloat(_real_value(BigFloat, ex); precision = precision)

Base.convert(::Type{T}, ex::GiacExpr) where {T<:AbstractFloat} = T(ex)
Base.convert(::Type{AbstractFloat}, ex::GiacExpr) = AbstractFloat(ex)


# ============================================================================
# Scalar Conversion Helpers
# ============================================================================

"""
    _convert_to_bool(g::GiacExpr)::Bool

Convert a boolean GiacExpr to Julia Bool.
The expression must represent "true" or "false".
"""
function _convert_to_bool(g::GiacExpr)::Bool
    str = string(g)
    return str == "true"
end

function _convert_to_int64(g::GiacExpr)::Int64
    with_giac_lock() do
        return _giac_to_int64(g.ptr)
    end
end

function _convert_to_float64(g::GiacExpr)::Float64
    with_giac_lock() do
        return _giac_to_float64(g.ptr)
    end
end

function _convert_to_bigint(g::GiacExpr)::BigInt
    # BigInt requires string parsing (GIAC stores as GMP internally)
    str = string(g)
    return parse(BigInt, str)
end

# A GIAC `STRNG` holds characters; its *printed* form is a source literal and
# carries the surrounding double quotes. Reading the value out of that literal
# would mean stripping the quotes and un-escaping: GIAC doubles an embedded
# quote, so `a"b` prints as `"a""b"`, and dropping the first and last character
# leaves `a""b`. The wrapper exposes the characters directly, so ask for them.
#
# `strng_value` dereferences the `STRNG` payload *without checking the tag* —
# handed anything else it segfaults the process rather than raising. So the tag
# must be checked, and it must be checked on the very object that is about to
# be dereferenced. `giac_type` is not that check: it re-parses the printed form
# and reports the type of the result, which is a different `Gen` from the
# cached one this reads. No expression is known where the two disagree, but the
# gap is not one to leave open in front of a segfault, so both the check and
# the read take the same `gen`.
function _convert_to_string(g::GiacExpr)::String
    return with_giac_lock() do
        gen = _get_gen_or_eval(g)
        t = T(GiacCxxBindings.type(gen))
        t == STRNG || throw(
            GiacError("Cannot read characters from a $t; expected STRNG", :type),
        )
        return String(GiacCxxBindings.strng_value(gen))
    end
end

# ============================================================================
# Compound Type Conversion Helpers
# ============================================================================

function _convert_to_rational(g::GiacExpr)
    num_expr = numer(g)
    den_expr = denom(g)

    num_type = giac_type(num_expr)
    den_type = giac_type(den_expr)

    # Check if either is BigInt (ZINT)
    if num_type == ZINT || den_type == ZINT
        num = to_julia(num_expr)::Union{Int64, BigInt}
        den = to_julia(den_expr)::Union{Int64, BigInt}
        return Rational{BigInt}(BigInt(num), BigInt(den))
    else
        num = _convert_to_int64(num_expr)
        den = _convert_to_int64(den_expr)
        return Rational{Int64}(num, den)
    end
end

function _convert_to_complex(g::GiacExpr)
    re_expr = real_part(g)
    im_expr = imag_part(g)

    re = to_julia(re_expr)
    im = to_julia(im_expr)

    # Promote to common type
    if re isa GiacExpr || im isa GiacExpr
        # If either part is symbolic, return as-is
        return g
    end

    T = promote_type(typeof(re), typeof(im))
    return Complex{T}(convert(T, re), convert(T, im))
end

# ============================================================================
# Vector Conversion with Type Narrowing
# ============================================================================

function _convert_to_vector(g::GiacExpr)
    n = _vector_length(g)

    if n == 0
        return Vector{GiacExpr}()
    end

    # First: get all elements as GiacExpr
    raw_elements = Vector{GiacExpr}(undef, n)
    for i in 1:n
        raw_elements[i] = _vector_element(g, i)
    end

    # Check if ALL elements can be fully converted (no symbolic remains)
    if all(_can_convert_fully, raw_elements)
        # Convert all elements to Julia types
        elements = Vector{Any}(undef, n)
        for i in 1:n
            elements[i] = to_julia(raw_elements[i])
        end
        return _narrow_vector_type(elements)
    else
        # At least one element is symbolic - keep all as GiacExpr
        return raw_elements
    end
end

"""
    _can_convert_fully(g::GiacExpr)::Bool

Check if a GiacExpr can be fully converted to native Julia types
(no GiacExpr remains in the result). For vectors, recursively checks all elements.
"""
function _can_convert_fully(g::GiacExpr)::Bool
    t = giac_type(g)
    if t == VECT
        # For vectors, recursively check all elements
        n = _vector_length(g)
        for i in 1:n
            elem = _vector_element(g, i)
            if !_can_convert_fully(elem)
                return false
            end
        end
        return true
    elseif t in (INT, DOUBLE, REAL, ZINT, FRAC, CPLX, STRNG)
        # Numeric and string types can be fully converted
        return true
    else
        # SYMB, IDNT, FUNC - symbolic, cannot fully convert
        return false
    end
end

"""
    _narrow_vector_type(elements::Vector{Any}) -> Vector

Narrow a Vector{Any} to the most specific element type.

For homogeneous numeric vectors, returns a typed vector.
For mixed numeric types, promotes to common numeric type.
For vectors containing non-numeric types, returns Vector{Any}.
"""
function _narrow_vector_type(elements::Vector{Any})
    if isempty(elements)
        return elements
    end

    types = unique(typeof.(elements))

    if length(types) == 1
        # Homogeneous type
        T = types[1]
        return convert(Vector{T}, elements)
    elseif all(T -> T <: Number, types)
        # Mixed numeric types - promote
        T = reduce(promote_type, types)
        return convert(Vector{T}, elements)
    else
        # Mixed types including non-numeric
        return elements
    end
end

# Internal vector access helpers
# Part of feature 031-fix-solve-to-julia: Use CxxWrap bindings exclusively
function _vector_length(g::GiacExpr)::Int
    with_giac_lock() do
        if GiacCxxBindings._have_library
            gen = _ptr_to_gen(g)
            if gen !== nothing
                # Use correct CxxWrap method name: vect_size() on Gen object
                return Int(GiacCxxBindings.vect_size(gen))
            end
        end
        # CxxWrap bindings required for vector conversion (031-fix-solve-to-julia)
        throw(GiacError("Vector conversion requires CxxWrap bindings", :type))
    end
end

function _vector_element(g::GiacExpr, i::Int)::GiacExpr
    with_giac_lock() do
        if GiacCxxBindings._have_library
            gen = _ptr_to_gen(g)
            if gen !== nothing
                # Use correct CxxWrap method name: vect_at(index) on Gen object
                # 0-based indexing in C++
                elem_gen = GiacCxxBindings.vect_at(gen, i - 1)
                return _gen_to_giacexpr(elem_gen)
            end
        end
        # CxxWrap bindings required for vector conversion (031-fix-solve-to-julia)
        throw(GiacError("Vector conversion requires CxxWrap bindings", :type))
    end
end

# ============================================================================
# Explicit Type Conversion via Base.convert
# ============================================================================

"""
    Base.convert(::Type{Int64}, g::GiacExpr) -> Int64

Convert an integer GiacExpr to Int64.
"""
function Base.convert(::Type{Int64}, g::GiacExpr)::Int64
    t = giac_type(g)
    if t == INT
        return _convert_to_int64(g)
    elseif t == ZINT
        big = _convert_to_bigint(g)
        if big > typemax(Int64) || big < typemin(Int64)
            throw(InexactError(:convert, Int64, big))
        end
        return Int64(big)
    else
        throw(MethodError(convert, (Int64, g)))
    end
end

"""
    Base.convert(::Type{Float64}, g::GiacExpr) -> Float64

Convert a numeric GiacExpr to Float64.
"""
function Base.convert(::Type{Float64}, g::GiacExpr)::Float64
    t = giac_type(g)
    if t == DOUBLE || t == REAL
        return _convert_to_float64(g)
    elseif t == INT
        return Float64(_convert_to_int64(g))
    elseif t == ZINT
        return Float64(_convert_to_bigint(g))
    elseif t == FRAC
        r = _convert_to_rational(g)
        return Float64(r)
    elseif is_constant(g)
        float(to_julia(g))
    else
        # Symbolic constants, `sqrt(2)`, the non-finite atoms: `AbstractFloat`
        # handles these, and it would be odd for `convert` to refuse what
        # `float` accepts. It raises `ArgumentError` for genuinely symbolic
        # input, where this used to raise `MethodError`.
        return Float64(AbstractFloat(g))
    end
end

# ============================================================================
# Numeric constructors
#
# `convert(T, ::GiacExpr)` was written for a handful of concrete targets and
# the matching constructors never were, so `convert(Int64, g)` worked while
# `Int64(g)` raised MethodError — and `convert` does not fall back to a
# constructor for a user type, so neither direction filled the other in.
#
# These delegate to the `convert` methods wherever one exists, so nothing
# about the existing behaviour changes, refusals included.
# ============================================================================

"""
    Integer(g::GiacExpr) -> Union{Int64,BigInt}

The integer behind an integer `GiacExpr`, staying `BigInt` when it does not
fit a machine word. `Int64(g)`, `Int32(g)`, `BigInt(g)` and the rest narrow
this, raising `InexactError` when the value does not fit the requested type.
"""
function Base.Integer(g::GiacExpr)
    t = giac_type(g)
    t == INT && return _convert_to_int64(g)
    t == ZINT && return _convert_to_bigint(g)
    throw(MethodError(Integer, (g,)))
end

# `Bool` is an `Integer` but is neither `Signed` nor `Unsigned`, which keeps
# it out of this and with the `convert(Bool, ...)` already defined below.
(::Type{T})(g::GiacExpr) where {T<:Union{Signed,Unsigned}} = T(Integer(g))

Base.convert(::Type{T}, g::GiacExpr) where {T<:Union{Signed,Unsigned}} = T(g)
Base.convert(::Type{Integer}, g::GiacExpr) = Integer(g)

"""
    Rational(g::GiacExpr) -> Rational

The rational behind a fraction or an integer `GiacExpr`.
"""
Base.Rational(g::GiacExpr) = convert(Rational, g)
(::Type{Rational{T}})(g::GiacExpr) where {T<:Integer} =
    convert(Rational{T}, convert(Rational, g))
Base.convert(::Type{Rational{T}}, g::GiacExpr) where {T<:Integer} = Rational{T}(g)

"""
    Complex(g::GiacExpr) -> Complex

The complex behind a `CPLX` `GiacExpr`; a real numeric one widens.
"""
Base.Complex(g::GiacExpr) = convert(Complex, g)
(::Type{Complex{T}})(g::GiacExpr) where {T<:Real} =
    convert(Complex{T}, convert(Complex, g))
Base.convert(::Type{Complex{T}}, g::GiacExpr) where {T<:Real} = Complex{T}(g)

"""
    Base.convert(::Type{Vector}, g::GiacExpr) -> Vector

Convert a vector GiacExpr to a Julia Vector.
"""
function Base.convert(::Type{Vector}, g::GiacExpr)::Vector
    if !is_vector(g)
        throw(MethodError(convert, (Vector, g)))
    end
    return _convert_to_vector(g)
end

"""
    Base.convert(::Type{Rational}, g::GiacExpr) -> Rational

Convert a fraction or integer GiacExpr to a Rational.
"""
function Base.convert(::Type{Rational}, g::GiacExpr)::Rational
    t = giac_type(g)
    if t == FRAC
        return _convert_to_rational(g)
    elseif t == INT
        return Rational(_convert_to_int64(g))
    elseif t == ZINT
        return Rational(_convert_to_bigint(g))
    else
        throw(MethodError(convert, (Rational, g)))
    end
end

"""
    Base.convert(::Type{Complex}, g::GiacExpr) -> Complex

Convert a complex GiacExpr to a Julia Complex.
"""
function Base.convert(::Type{Complex}, g::GiacExpr)::Complex
    t = giac_type(g)
    if t == CPLX
        return _convert_to_complex(g)
    elseif is_numeric(g)
        # Numeric but not complex - treat as real
        val = to_julia(g)
        return Complex(val)
    else
        throw(MethodError(convert, (Complex, g)))
    end
end

"""
    Base.convert(::Type{Bool}, g::GiacExpr) -> Bool

Convert a GiacExpr to a Julia Bool.

# Conversion Rules
- Boolean expressions (`true`, `false`, comparison results) convert directly
- Integer `0` converts to `false`
- Integer `1` converts to `true`
- All other values throw `InexactError`

# Example
```julia
convert(Bool, giac_eval("true"))   # true
convert(Bool, giac_eval("1==1"))   # true
convert(Bool, giac_eval("1"))      # true (integer 1 coerces to true)
convert(Bool, giac_eval("0"))      # false
convert(Bool, giac_eval("2"))      # throws InexactError
```

# See also
[`to_julia`](@ref), [`is_boolean`](@ref)
"""
function Base.convert(::Type{Bool}, g::GiacExpr)::Bool
    # Check for boolean expressions first
    if is_boolean(g)
        return _convert_to_bool(g)
    end

    # Allow integer 0/1 to convert to Bool (standard Julia behavior)
    t = giac_type(g)
    if t == INT
        val = _convert_to_int64(g)
        if val == 0
            return false
        elseif val == 1
            return true
        end
    end

    # All other values throw InexactError
    throw(InexactError(:convert, Bool, g))
end
