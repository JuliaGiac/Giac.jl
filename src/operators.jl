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
    with_giac_lock() do
        ptr = _giac_add(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Addition failed", :eval))
        end
        return GiacExpr(ptr)
    end
end

"""
    -(a::GiacExpr, b::GiacExpr)

Subtract two GIAC expressions.
"""
function Base.:-(a::GiacExpr, b::GiacExpr)::GiacExpr
    with_giac_lock() do
        ptr = _giac_sub(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Subtraction failed", :eval))
        end
        return GiacExpr(ptr)
    end
end

"""
    -(a::GiacExpr)

Negate a GIAC expression.
"""
function Base.:-(a::GiacExpr)::GiacExpr
    with_giac_lock() do
        ptr = _giac_neg(a.ptr)
        if ptr == C_NULL
            throw(GiacError("Negation failed", :eval))
        end
        return GiacExpr(ptr)
    end
end

"""
    *(a::GiacExpr, b::GiacExpr)

Multiply two GIAC expressions.
"""
function Base.:*(a::GiacExpr, b::GiacExpr)::GiacExpr
    with_giac_lock() do
        ptr = _giac_mul(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Multiplication failed", :eval))
        end
        return GiacExpr(ptr)
    end
end

"""
    /(a::GiacExpr, b::GiacExpr)

Divide two GIAC expressions.
"""
function Base.:/(a::GiacExpr, b::GiacExpr)::GiacExpr
    with_giac_lock() do
        ptr = _giac_div(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Division failed", :eval))
        end
        return GiacExpr(ptr)
    end
end

"""
    ^(a::GiacExpr, b::GiacExpr)

Raise a GIAC expression to a power.
"""
function Base.:^(a::GiacExpr, b::GiacExpr)::GiacExpr
    with_giac_lock() do
        ptr = _giac_pow(a.ptr, b.ptr)
        if ptr == C_NULL
            throw(GiacError("Exponentiation failed", :eval))
        end
        return GiacExpr(ptr)
    end
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
        return _giac_equal(a.ptr, b.ptr)
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
        ptr = _giac_matrix_mul(A.ptr, B.ptr)
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
        ptr = _giac_matrix_add(A.ptr, B.ptr)
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
        ptr = _giac_matrix_sub(A.ptr, B.ptr)
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
function Base.:*(A::GiacMatrix, c::Number)::GiacMatrix
    scalar = convert(GiacExpr, c)
    with_giac_lock() do
        ptr = _giac_matrix_scalar_mul(A.ptr, scalar.ptr)
        if ptr == C_NULL
            throw(GiacError("Scalar multiplication failed", :eval))
        end
        return GiacMatrix(ptr, A.rows, A.cols)
    end
end

Base.:*(c::Number, A::GiacMatrix) = A * c

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
function Base.:~(a::GiacExpr, b::GiacExpr)::GiacExpr
    eq_str = "$(string(a))=$(string(b))"
    return giac_eval(eq_str)
end

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
