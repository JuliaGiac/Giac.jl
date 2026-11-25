# Type introspection for Giac.jl
# Provides type predicates and component accessors for Gen/GiacExpr objects
#
# Part of feature 029-output-handling
# Updated for 041-scoped-type-enum: Uses GenTypes.T enum instead of GIAC_* constants

# ============================================================================
# Import GenTypes for T enum (041-scoped-type-enum)
# ============================================================================
using .GenTypes: T, INT, DOUBLE, ZINT, REAL, CPLX, POLY, IDNT, VECT, SYMB
using .GenTypes: SPOL1, FRAC, EXT, STRNG, FUNC, ROOT, MOD, USER, MAP, EQW, GROB, POINTER, FLOAT

# ============================================================================
# Import CxxWrap functions if available to extend them for GiacExpr
# ============================================================================
# Note: GiacCxxBindings may define is_integer, etc. for Gen type.
# We check and import these to add methods for GiacExpr.

# We'll define our own predicates - they won't conflict with CxxWrap's
# because Julia's method dispatch is based on argument types.
# The key is to ensure our functions are in the Giac module namespace.

# ============================================================================
# Type Introspection Functions
# ============================================================================

"""
    giac_type(g::GiacExpr) -> T

Return the GIAC type enum value for the expression.

Returns one of the `T` enum values from `Giac.GenTypes`:
`INT`, `DOUBLE`, `ZINT`, `REAL`, `CPLX`, `VECT`, `SYMB`, `IDNT`, `STRNG`, `FRAC`, `FUNC`, etc.

# Example
```julia
using Giac.GenTypes: T, INT, VECT

g = giac_eval("42")
giac_type(g) == INT  # true

g = giac_eval("[1, 2, 3]")
giac_type(g) == VECT  # true
```

See also: `Giac.GenTypes` module for type enum values
"""
function giac_type(g::GiacExpr)::T
    if g.ptr == C_NULL
        throw(GiacError("Cannot get type of null expression", :type))
    end

    with_giac_lock() do
        if GiacCxxBindings._have_library
            # Get the expression string and evaluate it to get a Gen object
            expr_str = string(g)
            try
                gen = GiacCxxBindings.giac_eval(expr_str)
                return T(GiacCxxBindings.type(gen))
            catch e
                @debug "Failed to get type via CxxWrap: $e"
            end
        end
        # Fallback: use existing _giac_expr_type and map to constants
        expr_type = _giac_expr_type(g.ptr)
        return _symbol_to_type_const(expr_type)
    end
end

"""
    subtype(g::GiacExpr) -> Int32

Return the subtype for vector expressions.

For vectors, returns `1` (sequence), `2` (set), `3` (list),
or `0` for standard vectors.

# Example
```julia
g = giac_eval("{1, 2, 3}")  # set
subtype(g) == 2  # true (set subtype)
```
"""
function subtype(g::GiacExpr)::Int32
    if g.ptr == C_NULL
        throw(GiacError("Cannot get subtype of null expression", :type))
    end

    with_giac_lock() do
        if GiacCxxBindings._have_library
            expr_str = string(g)
            try
                gen = GiacCxxBindings.giac_eval(expr_str)
                return Int32(GiacCxxBindings.subtype(gen))
            catch e
                @debug "Failed to get subtype via CxxWrap: $e"
            end
        end
        return Int32(0)  # Default subtype
    end
end

# Internal helper to convert symbol to type constant (returns T enum)
function _symbol_to_type_const(sym::Symbol)::T
    if sym == :integer
        return INT
    elseif sym == :float
        return DOUBLE
    elseif sym == :complex
        return CPLX
    elseif sym == :rational
        return FRAC
    elseif sym == :vector
        return VECT
    elseif sym == :matrix
        return VECT  # Matrices are stored as vectors in GIAC
    elseif sym == :symbolic
        return SYMB
    else
        return SYMB  # Default to symbolic
    end
end

# Internal helper to convert GiacExpr to CxxWrap Gen
# Used for vector operations and other CxxWrap-based conversions
function _ptr_to_gen(g::GiacExpr)
    if GiacCxxBindings._have_library
        # Try to retrieve stored Gen directly (no string serialization)
        gen = _get_gen(g.ptr)
        if gen !== nothing
            return gen
        end
        # Fallback: eval from string representation
        return GiacCxxBindings.giac_eval(string(g))
    end
    return nothing
end

# ============================================================================
# Type Predicates
# ============================================================================

"""
    is_integer(g::GiacExpr) -> Bool

Return `true` if the expression is an integer (`INT` or `ZINT`).

# Example
```julia
is_integer(giac_eval("42"))      # true
is_integer(giac_eval("3.14"))    # false
is_integer(giac_eval("x"))       # false
```
"""
function is_integer(g::GiacExpr)::Bool
    t = giac_type(g)
    return t == INT || t == ZINT
end

"""
    is_numeric(g::GiacExpr) -> Bool

Return `true` if the expression is a numeric value
(`INT`, `DOUBLE`, `ZINT`, or `REAL`).

# Example
```julia
is_numeric(giac_eval("42"))      # true
is_numeric(giac_eval("3.14"))    # true
is_numeric(giac_eval("x"))       # false
```
"""
function is_numeric(g::GiacExpr)::Bool
    t = giac_type(g)
    return t == INT || t == DOUBLE || t == ZINT || t == REAL
end

"""
    is_vector(g::GiacExpr) -> Bool

Return `true` if the expression is a vector/list/sequence (`VECT`).

# Example
```julia
is_vector(giac_eval("[1, 2, 3]"))  # true
is_vector(giac_eval("42"))         # false
```
"""
function is_vector(g::GiacExpr)::Bool
    return giac_type(g) == VECT
end

# is VECT also a matrix?
function is_vector_matrix(g::GiacExpr)::Bool
    is_vector(g) && subtype(g) == 11
end


"""
    is_symbolic(g::GiacExpr) -> Bool

Return `true` if the expression is symbolic (`SYMB`).

# Example
```julia
is_symbolic(giac_eval("sin(x)"))  # true
is_symbolic(giac_eval("x + 1"))   # true
is_symbolic(giac_eval("42"))      # false
```
"""
function is_symbolic(g::GiacExpr)::Bool
    return giac_type(g) == SYMB
end

"""
    is_identifier(g::GiacExpr) -> Bool

Return `true` if the expression is an identifier/variable (`IDNT`).

# Example
```julia
is_identifier(giac_eval("x"))       # true
is_identifier(giac_eval("x + 1"))   # false
```
"""
function is_identifier(g::GiacExpr)::Bool
    return giac_type(g) == IDNT
end

"""
    is_fraction(g::GiacExpr) -> Bool

Return `true` if the expression is a rational fraction (`FRAC`).

# Example
```julia
is_fraction(giac_eval("3/4"))    # true
is_fraction(giac_eval("42"))     # false
```
"""
function is_fraction(g::GiacExpr)::Bool
    return giac_type(g) == FRAC
end

"""
    is_complex(g::GiacExpr) -> Bool

Return `true` if the expression is a complex number (`CPLX`).

# Example
```julia
is_complex(giac_eval("3+4*i"))   # true
is_complex(giac_eval("42"))      # false
```
"""
function is_complex(g::GiacExpr)::Bool
    return giac_type(g) == CPLX
end

"""
    is_string(g::GiacExpr) -> Bool

Return `true` if the expression is a string (`STRNG`).

# Example
```julia
is_string(giac_eval("\"hello\""))  # true
is_string(giac_eval("42"))         # false
```
"""
function is_string(g::GiacExpr)::Bool
    return giac_type(g) == STRNG
end

"""
    is_boolean(g::GiacExpr) -> Bool

Return `true` if the expression represents a boolean value (`true` or `false`).

Note: GIAC represents booleans as integers internally (type `INT`), but
displays them as "true" or "false". This function detects boolean values by
checking the string representation.

# Example
```julia
is_boolean(giac_eval("true"))      # true
is_boolean(giac_eval("false"))     # true
is_boolean(giac_eval("1==1"))      # true (comparison returns boolean)
is_boolean(giac_eval("1"))         # false (integer, not boolean)
is_boolean(giac_eval("0"))         # false (integer, not boolean)
```

# See also
[`to_julia`](@ref), [`is_integer`](@ref)
"""
function is_boolean(g::GiacExpr)::Bool
    str = string(g)
    return str == "true" || str == "false"
end

"""
    is_constant(g::GiacExpr) -> Bool

Return `true` if the expression has no symbolic variables.

GIAC's recognized symbolic constants — `pi`, `e`, `i`, `infinity`, and
`undef` — are treated as constants (i.e. they do **not** count as free
symbols). Compound infinity forms like `inf`, `+inf`, `-inf`,
`+infinity`, and `-infinity` are wrappers around the bare `infinity`
atom and so are also classified as constants.

# Example
```julia
is_constant(giac_eval("x"))         # false
is_constant(giac_eval("sin(x)"))    # false
is_constant(giac_eval("1 == 1"))    # true (comparison returns constant)
is_constant(giac_eval("pi"))        # true
is_constant(giac_eval("0"))         # true (integer, not boolean)
is_constant(giac_eval("inf"))       # true (issue #19)
is_constant(giac_eval("-inf"))      # true
is_constant(giac_eval("undef"))     # true
is_constant(giac_eval("nan"))       # false (`nan` is a free identifier)
```

"""
is_constant(ex::GiacExpr) = !hasmatch(ex, x -> is_identifier(x) && !Constants.is_giac_constant(x))

"""
    hasmatch(ex::GiacExpr, pred) -> Bool

Recursively test whether any sub-expression of `ex` satisfies the predicate
`pred`. Walks every operand of compound expressions; for atomic expressions
(identifiers, numbers, …) the predicate is applied to `ex` itself.

This is the building block used by [`is_constant`](@ref) — it can also be
used directly for ad-hoc tree searches.

# Examples
```julia
Giac.hasmatch(giac_eval("sin(x) + 2"), Giac.is_identifier)  # true (contains x)
Giac.hasmatch(giac_eval("pi + 2"),    Giac.is_identifier)   # true (pi is an
                                                            # identifier; combine
                                                            # with is_giac_constant
                                                            # to exclude constants)
```
"""
function hasmatch(ex::GiacExpr, pred)
    if is_symbolic(ex)
        return any(Base.Fix2(hasmatch, pred), arguments(ex))
    end
    pred(ex)
end

"""
    free_symbols(ex::GiacExpr) -> GiacExpr

Return the free symbols in a symbolic expression
"""
function free_symbols(ex::GiacExpr)::GiacExpr
    return Commands.lname(ex)
end


# ============================================================================
# Component Access Functions
# ============================================================================

"""
    numer(g::GiacExpr) -> GiacExpr

Return the numerator of a fraction, or the value itself for integers.

# Example
```julia
numer(giac_eval("3/4"))   # GiacExpr representing 3
numer(giac_eval("5"))     # GiacExpr representing 5
```
"""
function numer(g::GiacExpr)::GiacExpr
    if g.ptr == C_NULL
        throw(GiacError("Cannot get numerator of null expression", :type))
    end

    t = giac_type(g)
    if t == INT || t == ZINT
        return g  # Integer is its own numerator
    elseif t == FRAC
        # Use existing _giac_rational_num or CxxWrap frac_num
        with_giac_lock() do
            if GiacCxxBindings._have_library
                gen = _ptr_to_gen(g)
                if gen !== nothing
                    num_gen = GiacCxxBindings.frac_num(gen)
                    return _gen_to_giacexpr(num_gen)
                end
            end
            # Fallback: get numerator value
            num_val = _giac_rational_num(g.ptr)
            return giac_eval(string(num_val))
        end
    else
        throw(GiacError("Gen is not a fraction or integer", :type))
    end
end

"""
    denom(g::GiacExpr) -> GiacExpr

Return the denominator of a fraction, or `1` for integers.

# Example
```julia
denom(giac_eval("3/4"))   # GiacExpr representing 4
denom(giac_eval("5"))     # GiacExpr representing 1
```
"""
function denom(g::GiacExpr)::GiacExpr
    if g.ptr == C_NULL
        throw(GiacError("Cannot get denominator of null expression", :type))
    end

    t = giac_type(g)
    if t == INT || t == ZINT
        return giac_eval("1")  # Integer has denominator 1
    elseif t == FRAC
        # Use existing _giac_rational_den or CxxWrap frac_den
        with_giac_lock() do
            if GiacCxxBindings._have_library
                gen = _ptr_to_gen(g)
                if gen !== nothing
                    den_gen = GiacCxxBindings.frac_den(gen)
                    return _gen_to_giacexpr(den_gen)
                end
            end
            # Fallback: get denominator value
            den_val = _giac_rational_den(g.ptr)
            return giac_eval(string(den_val))
        end
    else
        throw(GiacError("Gen is not a fraction or integer", :type))
    end
end

"""
    real_part(g::GiacExpr) -> GiacExpr

Return the real part of a complex number, or the value itself for non-complex.

# Example
```julia
real_part(giac_eval("3+4*i"))  # GiacExpr representing 3
real_part(giac_eval("5"))      # GiacExpr representing 5
```
"""
function real_part(g::GiacExpr)::GiacExpr
    if g.ptr == C_NULL
        throw(GiacError("Cannot get real part of null expression", :type))
    end

    t = giac_type(g)
    if t == CPLX
        with_giac_lock() do
            if GiacCxxBindings._have_library
                gen = _ptr_to_gen(g)
                if gen !== nothing
                    re_gen = GiacCxxBindings.cplx_re(gen)
                    return _gen_to_giacexpr(re_gen)
                end
            end
            # Fallback: get real part value
            re_val = _giac_complex_real(g.ptr)
            return giac_eval(string(re_val))
        end
    else
        return g  # Non-complex is its own real part
    end
end

"""
    imag_part(g::GiacExpr) -> GiacExpr

Return the imaginary part of a complex number, or `0` for non-complex.

# Example
```julia
imag_part(giac_eval("3+4*i"))  # GiacExpr representing 4
imag_part(giac_eval("5"))      # GiacExpr representing 0
```
"""
function imag_part(g::GiacExpr)::GiacExpr
    if g.ptr == C_NULL
        throw(GiacError("Cannot get imaginary part of null expression", :type))
    end

    t = giac_type(g)
    if t == CPLX
        with_giac_lock() do
            if GiacCxxBindings._have_library
                gen = _ptr_to_gen(g)
                if gen !== nothing
                    im_gen = GiacCxxBindings.cplx_im(gen)
                    return _gen_to_giacexpr(im_gen)
                end
            end
            # Fallback: get imaginary part value
            im_val = _giac_complex_imag(g.ptr)
            return giac_eval(string(im_val))
        end
    else
        return giac_eval("0")  # Non-complex has zero imaginary part
    end
end

"""
    symb_funcname(g::GiacExpr) -> String

Return the function name of a symbolic expression.

# Example
```julia
symb_funcname(giac_eval("sin(x)"))  # "sin"
```
"""
function symb_funcname(g::GiacExpr)::String
    if g.ptr == C_NULL
        throw(GiacError("Cannot get function name of null expression", :type))
    end

    if giac_type(g) != SYMB
        throw(GiacError("Gen is not symbolic", :type))
    end

    with_giac_lock() do
        if GiacCxxBindings._have_library
            gen = _ptr_to_gen(g)
            if gen !== nothing
                # Use symb_sommet_name (the actual C++ binding name)
                return GiacCxxBindings.symb_sommet_name(gen)
            end
        end
        # Fallback: parse from string representation
        expr_str = string(g)
        m = match(r"^(\w+)\(", expr_str)
        return m !== nothing ? String(m.captures[1]) : ""
    end
end



"""
    symb_argument(g::GiacExpr) -> GiacExpr

Return the argument (operand) of a symbolic expression.

# Example
```julia
arg = symb_argument(giac_eval("sin(x)"))  # GiacExpr representing x
```
"""
function symb_argument(g::GiacExpr)::GiacExpr
    if g.ptr == C_NULL
        throw(GiacError("Cannot get argument of null expression", :type))
    end

    if giac_type(g) != SYMB
        throw(GiacError("Gen is not symbolic", :type))
    end

    with_giac_lock() do
        if GiacCxxBindings._have_library
            gen = _ptr_to_gen(g)
            if gen !== nothing
                # Use symb_feuille (the actual C++ binding name)
                arg_gen = GiacCxxBindings.symb_feuille(gen)
                return _gen_to_giacexpr(arg_gen)
            end
        end
        # Fallback: extract argument from string representation
        expr_str = string(g)
        m = match(r"^\w+\((.+)\)$", expr_str)
        return m !== nothing ? giac_eval(String(m.captures[1])) : g
    end
end

## TermInterface names
iscall(g::GiacExpr)::Bool = giac_type(g) == Giac.SYMB

function operation(g::GiacExpr)
    iscall(g) || throw(ArgumentError("expression is not a function call"))
    fn = Symbol(symb_funcname(g))
    hasproperty(Giac.Commands, fn) && return getproperty(Giac.Commands, fn)
    hasproperty(Giac, fn) && return getproperty(Giac, fn)
    hasproperty(Base, fn) && return getproperty(Base, fn)
    hasproperty(LinearAlgebra, fn) && return getproperty(LinearAlgebra, fn)
    throw(ArgumentError("Cannot locate function `$fn` in Giac.Commands, Giac, Base, or LinearAlgebra"))
end

function arguments(g::GiacExpr)::Vector{GiacExpr}
    iscall(g) || throw(ArgumentError("expression is not a function call"))
    collect(GiacExpr, symb_argument(g))
end

maketerm(::Type{GiacExpr}, op, args, metadata=nothing)::GiacExpr = GiacExpr(op(args...))


# Internal helper to convert Gen to GiacExpr
function _gen_to_giacexpr(gen)
    # Convert CxxWrap Gen to GiacExpr via string representation
    if gen !== nothing
        # GiacCxxBindings.to_string returns a CxxWrap StdString, convert to Julia String
        std_str = GiacCxxBindings.to_string(gen)
        julia_str = String(std_str)
        return giac_eval(julia_str)
    end
    throw(GiacError("Cannot convert Gen to GiacExpr", :type))
end
