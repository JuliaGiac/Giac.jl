# Operator overloading for GiacExpr
# Enables natural mathematical syntax for symbolic expressions

# =============================================================================
# Arithmetic Operators
# =============================================================================

"""
    +(a::GiacExpr, b::GiacExpr)

Add two GIAC expressions.
"""
function Base.:+(a::GiacExpr, b::GiacExpr)::GiacExpr
    r = with_giac_lock() do
        ptr = GC.@preserve a b _giac_add(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Addition failed", :eval))
        end
        return GiacExpr(ptr)
    end
    return _both_sides(+, a, b, r)
end

"""
    -(a::GiacExpr, b::GiacExpr)

Subtract two GIAC expressions.
"""
function Base.:-(a::GiacExpr, b::GiacExpr)::GiacExpr
    r = with_giac_lock() do
        ptr = GC.@preserve a b _giac_sub(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Subtraction failed", :eval))
        end
        return GiacExpr(ptr)
    end
    return _both_sides(-, a, b, r)
end

"""
    -(a::GiacExpr)

Negate a GIAC expression.
"""
function Base.:-(a::GiacExpr)::GiacExpr
    r = with_giac_lock() do
        ptr = GC.@preserve a _giac_neg(a.ptr)
        if ptr == C_NULL
            throw(GiacError("Negation failed", :eval))
        end
        return GiacExpr(ptr)
    end
    return _both_sides(-, a, r)
end

"""
    *(a::GiacExpr, b::GiacExpr)

Multiply two GIAC expressions.
"""
function Base.:*(a::GiacExpr, b::GiacExpr)::GiacExpr
    r = with_giac_lock() do
        ptr = GC.@preserve a b _giac_mul(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Multiplication failed", :eval))
        end
        return GiacExpr(ptr)
    end
    return _both_sides(*, a, b, r)
end

"""
    /(a::GiacExpr, b::GiacExpr)

Divide two GIAC expressions.
"""
function Base.:/(a::GiacExpr, b::GiacExpr)::GiacExpr
    r = with_giac_lock() do
        ptr = GC.@preserve a b _giac_div(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Division failed", :eval))
        end
        return GiacExpr(ptr)
    end
    return _both_sides(/, a, b, r)
end

"""
    ^(a::GiacExpr, b::GiacExpr)

Raise a GIAC expression to a power.
"""
function Base.:^(a::GiacExpr, b::GiacExpr)::GiacExpr
    r = with_giac_lock() do
        ptr = GC.@preserve a b _giac_pow(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Exponentiation failed", :eval))
        end
        return GiacExpr(ptr)
    end
    return _both_sides(^, a, b, r)
end

"""
    ^(a::GiacExpr, n::Number)

Raise a GIAC expression to a power.
"""
Base.:^(a::GiacExpr, b::Number) = ^(promote(a, b)...)

"""
    ^(a::Number, n::GiacExpr)

Raise a number to a GIAC expression
"""
Base.:^(a::Number, b::GiacExpr) = ^(promote(a, b)...)

# =============================================================================
# Mixed-type arithmetic (GiacExpr with Julia numbers)
# =============================================================================

# Addition
Base.:+(a::GiacExpr, b::Number) = a + convert(GiacExpr, b)
Base.:+(a::Number, b::GiacExpr) = convert(GiacExpr, a) + b

# Subtraction
Base.:-(a::GiacExpr, b::Number) = a - convert(GiacExpr, b)
Base.:-(a::Number, b::GiacExpr) = convert(GiacExpr, a) - b

# Multiplication
Base.:*(a::GiacExpr, b::Number) = a * convert(GiacExpr, b)
Base.:*(a::Number, b::GiacExpr) = convert(GiacExpr, a) * b

# Division
Base.:/(a::GiacExpr, b::Number) = a / convert(GiacExpr, b)
Base.:/(a::Number, b::GiacExpr) = convert(GiacExpr, a) / b

# Rational Division (fallback to exact symbolic division)
Base.://(a::GiacExpr, b::GiacExpr) = a / b
Base.://(a::GiacExpr, b::Number) = a / b
Base.://(a::Number, b::GiacExpr) = a / b

# =============================================================================
# Comparison Operators
# =============================================================================

"""
    ==(a::GiacExpr, b::GiacExpr)

Check if two GIAC expressions are equal.
Note: This performs symbolic equality check, not numerical.
"""
function Base.:(==)(a::GiacExpr, b::GiacExpr)::Bool
    with_giac_lock() do
        return GC.@preserve a b _giac_equal(a.ptr, b.ptr)
    end
end

Base.:(==)(a::GiacExpr, b::Number) = a == convert(GiacExpr, b)
Base.:(==)(a::Number, b::GiacExpr) = convert(GiacExpr, a) == b

"""
    hash(expr::GiacExpr, h::UInt)

Hash a GIAC expression for use in dictionaries and sets.
"""
function Base.hash(expr::GiacExpr, h::UInt)::UInt
    # Use string representation for hashing
    return hash(string(expr), h)
end

# =============================================================================
# Symbolic Comparison Operators (064-symbolic-comparison-operators)
# =============================================================================
# These operators return GiacExpr (symbolic inequalities), NOT Bool.
# This enables natural syntax like: assume(x > 0), additionally(x < 10)
# Note: isless is intentionally NOT overridden to preserve sort/min/max semantics.

"""
    <(a::GiacExpr, b::GiacExpr) -> GiacExpr

Create a symbolic less-than inequality from two GIAC expressions.

Returns a `GiacExpr` representing the inequality (not a `Bool`).

# Examples
```julia
@giac_var x y
ineq = x < y           # Creates symbolic inequality x<y
assume(x < giac_eval("10"))  # Use with assume
```
"""
function Base.:<(a::GiacExpr, b::GiacExpr)::GiacExpr
    return giac_eval("$(string(a))<$(string(b))")
end

"""
    >(a::GiacExpr, b::GiacExpr) -> GiacExpr

Create a symbolic greater-than inequality from two GIAC expressions.

Returns a `GiacExpr` representing the inequality (not a `Bool`).

# Examples
```julia
@giac_var x y
ineq = x > y           # Creates symbolic inequality x>y
assume(x > giac_eval("0"))   # Assume x is positive
```
"""
function Base.:>(a::GiacExpr, b::GiacExpr)::GiacExpr
    return giac_eval("$(string(a))>$(string(b))")
end

"""
    <=(a::GiacExpr, b::GiacExpr) -> GiacExpr

Create a symbolic less-than-or-equal inequality from two GIAC expressions.

Returns a `GiacExpr` representing the inequality (not a `Bool`).

# Examples
```julia
@giac_var x y
ineq = x <= y           # Creates symbolic inequality x<=y
```
"""
function Base.:<=(a::GiacExpr, b::GiacExpr)::GiacExpr
    return giac_eval("$(string(a))<=$(string(b))")
end

"""
    >=(a::GiacExpr, b::GiacExpr) -> GiacExpr

Create a symbolic greater-than-or-equal inequality from two GIAC expressions.

Returns a `GiacExpr` representing the inequality (not a `Bool`).

# Examples
```julia
@giac_var x y
ineq = x >= y           # Creates symbolic inequality x>=y
```
"""
function Base.:>=(a::GiacExpr, b::GiacExpr)::GiacExpr
    return giac_eval("$(string(a))>=$(string(b))")
end

# Mixed-type comparisons (GiacExpr with Julia numbers)
Base.:<(a::GiacExpr, b::Number) = a < convert(GiacExpr, b)
Base.:<(a::Number, b::GiacExpr) = convert(GiacExpr, a) < b

Base.:>(a::GiacExpr, b::Number) = a > convert(GiacExpr, b)
Base.:>(a::Number, b::GiacExpr) = convert(GiacExpr, a) > b

Base.:<=(a::GiacExpr, b::Number) = a <= convert(GiacExpr, b)
Base.:<=(a::Number, b::GiacExpr) = convert(GiacExpr, a) <= b

Base.:>=(a::GiacExpr, b::Number) = a >= convert(GiacExpr, b)
Base.:>=(a::Number, b::GiacExpr) = convert(GiacExpr, a) >= b

# =============================================================================
# Symbolic Logical Operators (064-symbolic-comparison-operators)
# =============================================================================
# These operators combine symbolic inequalities using GIAC's `and`/`or`.
# Primary use case: assume((x > 0) & (x < 10)) for interval constraints.
# Note: Julia's && and || cannot be overloaded (short-circuit operators),
# so we use & and | (bitwise operators) instead.

"""
    &(a::GiacExpr, b::GiacExpr) -> GiacExpr

Combine two symbolic expressions with GIAC's logical `and`.

This enables interval constraints with `assume`:

# Examples
```julia
@giac_var x
assume((x > 0) & (x < 10))   # x in (0, 10)
```
"""
function Base.:&(a::GiacExpr, b::GiacExpr)::GiacExpr
    return giac_eval("($(string(a))) and ($(string(b)))")
end

"""
    |(a::GiacExpr, b::GiacExpr) -> GiacExpr

Combine two symbolic expressions with GIAC's logical `or`.

# Examples
```julia
@giac_var x
expr = (x < -1) | (x > 1)   # x outside [-1, 1]
```
"""
function Base.:|(a::GiacExpr, b::GiacExpr)::GiacExpr
    return giac_eval("($(string(a))) or ($(string(b)))")
end

# =============================================================================
# Matrix Operators
# =============================================================================

"""
    *(A::GiacMatrix, B::GiacMatrix)

Matrix multiplication.
"""
function Base.:*(A::GiacMatrix, B::GiacMatrix)::GiacMatrix
    if A.cols != B.rows
        throw(DimensionMismatch("Matrix dimensions do not match for multiplication: $(size(A)) * $(size(B))"))
    end

    with_giac_lock() do
        ptr = GC.@preserve A B _giac_matrix_mul(A.ptr, B.ptr)
        if ptr == C_NULL
            throw(GiacError("Matrix multiplication failed", :eval))
        end
        return GiacMatrix(ptr, A.rows, B.cols)
    end
end

"""
    +(A::GiacMatrix, B::GiacMatrix)

Matrix addition.
"""
function Base.:+(A::GiacMatrix, B::GiacMatrix)::GiacMatrix
    if A.rows != B.rows || A.cols != B.cols
        throw(DimensionMismatch("Matrix dimensions do not match for addition"))
    end

    with_giac_lock() do
        ptr = GC.@preserve A B _giac_matrix_add(A.ptr, B.ptr)
        if ptr == C_NULL
            throw(GiacError("Matrix addition failed", :eval))
        end
        return GiacMatrix(ptr, A.rows, A.cols)
    end
end

"""
    -(A::GiacMatrix, B::GiacMatrix)

Matrix subtraction.
"""
function Base.:-(A::GiacMatrix, B::GiacMatrix)::GiacMatrix
    if A.rows != B.rows || A.cols != B.cols
        throw(DimensionMismatch("Matrix dimensions do not match for subtraction"))
    end

    with_giac_lock() do
        ptr = GC.@preserve A B _giac_matrix_sub(A.ptr, B.ptr)
        if ptr == C_NULL
            throw(GiacError("Matrix subtraction failed", :eval))
        end
        return GiacMatrix(ptr, A.rows, A.cols)
    end
end

"""
    *(A::GiacMatrix, c::Number)

Scalar multiplication of matrix.
"""
Base.:*(A::GiacMatrix, c::Number) = _scaled_matrix(A, convert(GiacExpr, c))

function _scaled_matrix(A::GiacMatrix, scalar::GiacExpr)::GiacMatrix
    with_giac_lock() do
        ptr = GC.@preserve A scalar _giac_matrix_scalar_mul(A.ptr, scalar.ptr)
        if ptr == C_NULL
            throw(GiacError("Scalar multiplication failed", :eval))
        end
        return GiacMatrix(ptr, A.rows, A.cols)
    end
end

Base.:*(c::Number, A::GiacMatrix) = A * c

# A symbolic scale factor keeps a Giac matrix a Giac matrix, as a number does. (These are more
# specific than the methods for any array, which give a `Matrix{GiacExpr}`.) Ported from Kahli
# Burke's `ergonomics` branch.
Base.:*(A::GiacMatrix, c::GiacExpr) = _scaled_matrix(A, c)
Base.:*(c::GiacExpr, A::GiacMatrix) = A * c
Base.:/(A::GiacMatrix, c::Number) = A * (one(GiacExpr) / convert(GiacExpr, c))   # exact: σ/2, not σ*0.5
Base.:/(A::GiacMatrix, c::GiacExpr) = A * (one(GiacExpr) / c)
Base.:-(A::GiacMatrix) = A * -1

"""
    kron(A::GiacMatrix, B::GiacMatrix) -> GiacMatrix

The Kronecker product `A ⊗ B`: each entry of `A` times the whole of `B`.
"""
Base.kron(A::GiacMatrix, B::GiacMatrix) = GiacMatrix(kron(Matrix(A), Matrix(B)))

# =============================================================================
# Equation Operator (~) - 024-equation-syntax
# =============================================================================

"""
    ~(a::GiacExpr, b::GiacExpr) -> GiacExpr

Create a symbolic equation from two GIAC expressions.

This operator follows the Julia Symbolics.jl convention where `~` creates
an equation (equality relation) rather than a boolean comparison.

# Arguments
- `a::GiacExpr`: Left-hand side of the equation
- `b::GiacExpr`: Right-hand side of the equation

# Returns
- `GiacExpr`: A GIAC expression representing the equation `a = b`

# Examples
```julia
@giac_var x
eq = x^2 - 1 ~ giac_eval("0")  # Creates equation x^2-1=0
solve(eq, x)                    # Solves for x: [-1, 1]

# Multiple variable equation
@giac_several_vars x y
eq = x + y ~ giac_eval("10")   # Creates equation x+y=10
```

# See also
- [`==`](@ref): Boolean equality check (returns `Bool`)
- [`solve`](@ref): Solve equations
"""
# Built by GIAC's `equal`, so the sides are not printed and parsed again (a float keeps its
# digits). Ported from Kahli Burke's `ergonomics` branch.
Base.:~(a::GiacExpr, b::GiacExpr)::GiacExpr = invoke_cmd(:equal, a, b)

"""
    ~(a::GiacExpr, b::Number) -> GiacExpr

Create a symbolic equation from a GIAC expression and a number.

# Examples
```julia
@giac_var x
eq = x ~ 5      # Creates equation x=5
eq = x^2 ~ 4    # Creates equation x^2=4
```
"""
function Base.:~(a::GiacExpr, b::Number)::GiacExpr
    return a ~ convert(GiacExpr, b)
end

"""
    ~(a::Number, b::GiacExpr) -> GiacExpr

Create a symbolic equation from a number and a GIAC expression.

# Examples
```julia
@giac_var x
eq = 0 ~ x^2 - 1    # Creates equation 0=x^2-1
eq = 10 ~ x + 5     # Creates equation 10=x+5
```
"""
function Base.:~(a::Number, b::GiacExpr)::GiacExpr
    return convert(GiacExpr, a) ~ b
end

# =============================================================================
# Promotion and Conversion
# =============================================================================

# Enable automatic conversion in mixed operations
Base.promote_rule(::Type{GiacExpr}, ::Type{<:Number}) = GiacExpr
"""
    convert(::Type{GiacExpr}, x::Number) -> GiacExpr

Convert a Julia number to a GIAC expression.

# Supported Types

- **Integer/Float**: Direct string conversion via `giac_eval`
- **Rational**: Uses division operator (`1//2` → `1/2`)
- **Complex**: Uses arithmetic with GIAC's `i` unit (`1+2im` → `1+2*i`)
- **Irrational{:π}**: Maps to GIAC's `pi` constant
- **Irrational{:ℯ}**: Maps to GIAC's `e` constant

# Special Values

- `Inf` is converted to GIAC's `inf` (positive infinity)
- `-Inf` is converted to GIAC's `-inf` (negative infinity)

# Examples
```julia
convert(GiacExpr, 42)       # Returns GiacExpr representing 42
convert(GiacExpr, 1//2)     # Returns GiacExpr representing 1/2
convert(GiacExpr, 1+2im)    # Returns GiacExpr representing 1+2*i
convert(GiacExpr, π)        # Returns GiacExpr representing pi
convert(GiacExpr, ℯ)        # Returns GiacExpr representing e
convert(GiacExpr, Inf)      # Returns GiacExpr representing +infinity
```

See also: Type-specific methods for [`Rational`](@ref), [`Complex`](@ref),
[`Irrational{:π}`](@ref), [`Irrational{:ℯ}`](@ref).
"""
function Base.convert(::Type{GiacExpr}, x::Number)
    if x isa AbstractFloat && isinf(x)
        return giac_eval(x > 0 ? "inf" : "-inf")
    else
        return giac_eval(string(x))
    end
end

"""
    convert(::Type{GiacExpr}, x::Bool) -> GiacExpr

`true` and `false` are the integers 1 and 0, as in Julia arithmetic (`Bool <: Integer`). This is
what makes `I` (a `UniformScaling{Bool}`) give 1s and 0s in symbolic matrices, including
concatenations like `[A I; I A']`. Giac's logical constants are `giac_eval("true")` and
`giac_eval("false")`. Ported from Kahli Burke's `ergonomics` branch.
"""
Base.convert(::Type{GiacExpr}, x::Bool) = convert(GiacExpr, Int(x))

# =============================================================================
# Type-Specific Conversions (043-fix-rational-arithmetic)
# These methods use C++ operators instead of string parsing for better
# performance and correctness.
# =============================================================================

"""
    convert(::Type{GiacExpr}, x::Rational) -> GiacExpr

Convert a Julia Rational number to a GIAC expression using the division operator.

Uses the C++ `_giac_div` function (tier 1/2) instead of string parsing,
which correctly handles the conversion from Julia's `//` syntax to GIAC's `/`.

# Examples
```julia
convert(GiacExpr, 1//2)     # Returns GiacExpr representing 1/2
convert(GiacExpr, -3//4)    # Returns GiacExpr representing -3/4
convert(GiacExpr, 22//7)    # Returns GiacExpr representing 22/7
```
"""
function Base.convert(::Type{GiacExpr}, x::Rational)
    num = convert(GiacExpr, numerator(x))
    den = convert(GiacExpr, denominator(x))
    return num / den
end

# `GiacExpr(3//4)`, `GiacExpr.(M)` for a numeric matrix: the same as `convert`
GiacExpr(x::Number) = convert(GiacExpr, x)

"""
    convert(::Type{GiacExpr}, x::Complex) -> GiacExpr

Convert a Julia Complex number to a GIAC expression using arithmetic operators.

Uses C++ `_giac_add` and `_giac_mul` functions (tier 1/2) to construct
`real + imag * i` where `i` is GIAC's imaginary unit.

# Examples
```julia
convert(GiacExpr, 1 + 2im)    # Returns GiacExpr representing 1+2*i
convert(GiacExpr, 3.5 + 0im)  # Returns GiacExpr representing 3.5
convert(GiacExpr, 2im)        # Returns GiacExpr representing 2*i
```
"""
function Base.convert(::Type{GiacExpr}, x::Complex)
    re = convert(GiacExpr, real(x))
    im_part = convert(GiacExpr, imag(x))
    i_unit = giac_eval("i")
    return re + im_part * i_unit
end

"""
    convert(::Type{GiacExpr}, ::Irrational{:π}) -> GiacExpr

Convert Julia's π constant to GIAC's `pi` constant.

# Examples
```julia
convert(GiacExpr, π)    # Returns GiacExpr representing pi
```
"""
function Base.convert(::Type{GiacExpr}, ::Irrational{:π})
    return giac_eval("pi")
end

"""
    convert(::Type{GiacExpr}, ::Irrational{:ℯ}) -> GiacExpr

Convert Julia's ℯ (Euler's number) constant to GIAC's `e` constant.

# Examples
```julia
convert(GiacExpr, ℯ)    # Returns GiacExpr representing e
```
"""
function Base.convert(::Type{GiacExpr}, ::Irrational{:ℯ})
    return giac_eval("e")
end

# =============================================================================
# Numerator / Denominator (057-numerator-denominator-methods)
# =============================================================================

"""
    numerator(g::GiacExpr) -> GiacExpr

Return the numerator of a GIAC expression. Delegates to GIAC's `numer` command,
which handles both numeric fractions (e.g., `25/15`) and symbolic rational
expressions (e.g., `(x^3-1)/(x^2-1)`).

# Examples
```julia
numerator(giac_eval("25/15"))          # 5
@giac_var x
numerator((x^3 - 1) / (x^2 - 1))     # x^2+x+1
```
"""
Base.numerator(g::GiacExpr)::GiacExpr = invoke_cmd(:numer, g)

"""
    denominator(g::GiacExpr) -> GiacExpr

Return the denominator of a GIAC expression. Delegates to GIAC's `denom` command,
which handles both numeric fractions (e.g., `25/15`) and symbolic rational
expressions (e.g., `(x^3-1)/(x^2-1)`).

# Examples
```julia
denominator(giac_eval("25/15"))        # 3
@giac_var x
denominator((x^3 - 1) / (x^2 - 1))   # x+1
```
"""
Base.denominator(g::GiacExpr)::GiacExpr = invoke_cmd(:denom, g)

# =============================================================================
# Iteration support for expression components (future enhancement)
# =============================================================================

# These would be implemented when we add expression tree traversal
# Base.iterate(expr::GiacExpr) = ...
# Base.length(expr::GiacExpr) = ...

# ============================================================================
# Approximate equality (design and tests from the `ergonomics` branch by
# Kahli Burke, implemented on Giac.jl's current API)
# ============================================================================

"""
    isapprox(a::GiacExpr, b::GiacExpr; atol = 0, rtol, nans = false)
    a ≈ b

Approximate equality, with Julia's tolerances.

- Expressions without free symbols are compared by their numeric values:
  `sqrt(GiacExpr(2)) ≈ 1.4142135623730951`.
- Expressions in symbols are approximately equal when they are equal (`==`), or
  when the numeric coefficients of their monomials are approximately equal, the
  coefficients being compared as one vector: `1.0000000001x + y ≈ x + y`.
  Non-rational parts such as `sin(x)` count as variables of the monomials.
- An expression with no numeric value, or a coefficient without one, is
  approximately equal only to what it equals.

A `GiacExpr` can also be compared with a Julia number, in either order.
"""
function Base.isapprox(a::GiacExpr, b::GiacExpr;
                       atol::Real = 0,
                       rtol::Real = atol > 0 ? 0 : sqrt(eps(Float64)),
                       nans::Bool = false)
    isequal(a, b) && return true
    if !_has_free_symbols(a) && !_has_free_symbols(b)
        x, y = _approx_value(a), _approx_value(b)
        (x === nothing || y === nothing) && return a == b
        return isapprox(x, y; atol, rtol, nans)
    end
    a == b && return true
    ca, cb = _monomial_coefficients(a, b)
    ca === nothing && return false
    monomials = collect(union(keys(ca), keys(cb)))
    x = [get(ca, m, 0.0) for m in monomials]
    y = [get(cb, m, 0.0) for m in monomials]
    return isapprox(x, y; atol, rtol, nans)
end
Base.isapprox(a::GiacExpr, b::Number; kw...) = isapprox(a, convert(GiacExpr, b); kw...)
Base.isapprox(a::Number, b::GiacExpr; kw...) = isapprox(convert(GiacExpr, a), b; kw...)

_giac_list(e::GiacExpr) = GiacExpr[t for t in e]

_has_free_symbols(e::GiacExpr) = !isempty(_giac_list(invoke_cmd(:lname, e)))

# The value of an expression with no free symbols as a Float64 or ComplexF64,
# or `nothing` if it has none.
function _approx_value(e::GiacExpr)
    v = try
        to_julia(invoke_cmd(:evalf, e))
    catch
        return nothing
    end
    v isa Real && return Float64(v)
    v isa Complex && return ComplexF64(v)
    return nothing
end

# The coefficients of `a` and `b` as polynomials in the same variables: each
# non-rational part of either (`lvar`, e.g. `x` or `sin(x)`) is replaced by a
# fresh variable. Returns two `Dict(exponents => coefficient)`, or
# `(nothing, nothing)` if a coefficient has no numeric value or the
# expressions are not polynomial in those parts.
function _monomial_coefficients(a::GiacExpr, b::GiacExpr)
    atoms = unique!(vcat(_giac_list(invoke_cmd(:lvar, a)), _giac_list(invoke_cmd(:lvar, b))))
    # fresh variables that no value or assumption of the session captures
    return with_fresh_identifiers(length(atoms); prefix = "giacjl_isapprox") do fresh...
        fresh = collect(GiacExpr, fresh)
        polys = map((a, b)) do e
            isempty(atoms) && return e
            invoke_cmd(:expand, invoke_cmd(:subst, e, atoms, fresh))
        end
        ca = _coefficient_dict(polys[1], fresh)
        cb = _coefficient_dict(polys[2], fresh)
        (ca === nothing || cb === nothing) && return (nothing, nothing)
        return ca, cb
    end
end

function _coefficient_dict(p::GiacExpr, vars::Vector{GiacExpr},
                           prefix::Vector{Int} = Int[],
                           out::Dict{Vector{Int},Number} = Dict{Vector{Int},Number}())
    if isempty(vars)
        v = _approx_value(p)
        v === nothing && return nothing
        iszero(v) || (out[copy(prefix)] = v)
        return out
    end
    coeffs = try
        _giac_list(invoke_cmd(:coeffs, p, vars[1]))
    catch
        return nothing
    end
    degree = length(coeffs) - 1
    for (i, c) in enumerate(coeffs)
        r = _coefficient_dict(c, vars[2:end], [prefix; degree - i + 1], out)
        r === nothing && return nothing
    end
    return out
end
