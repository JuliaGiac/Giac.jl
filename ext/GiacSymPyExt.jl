# Extension module for SymPy.jl integration
# Provides bidirectional conversion between GiacExpr and SymPy.Sym types:
#   to_sympy(::GiacExpr)  -> Sym
#   to_giac(::Sym)        -> GiacExpr
# Requires the GIAC C++ wrapper library
#
# Feature 080-sympy-bridge: bidirectional bridge between Giac.jl and SymPy.jl.

module GiacSymPyExt

using Giac
using SymPy
using CxxWrap: StdVector

# ============================================================================
# GIAC to Julia Name Mapping
# Only needed for function names that differ between GIAC and Julia/SymPy
# ============================================================================

"""
    GIAC_NAME_MAPPING

Dictionary mapping GIAC function names to Julia functions where names differ.
For functions with identical names, Julia functions are resolved dynamically
from Base (SymPy.jl overloads the same Base functions on `Sym`).
"""
const GIAC_NAME_MAPPING = Dict{String, Function}(
    "ln" => log,  # GIAC uses "ln", Julia/SymPy use "log"
)

"""
    _get_julia_function(giac_name::String) -> Union{Function, Nothing}

Get the Julia function corresponding to a GIAC function name.
First checks `GIAC_NAME_MAPPING` for name differences, then tries to resolve
from Base using the same name. Returns `nothing` if not found.
"""
function _get_julia_function(giac_name::String)::Union{Function, Nothing}
    if haskey(GIAC_NAME_MAPPING, giac_name)
        return GIAC_NAME_MAPPING[giac_name]
    end
    sym = Symbol(giac_name)
    if isdefined(Base, sym)
        f = getfield(Base, sym)
        if f isa Function
            return f
        end
    end
    return nothing
end

# ============================================================================
# Locking
#
# GIAC is not thread-safe: every wrapper call runs under the GIAC lock. Python
# is not either, and SymPy is reached through PyCall, on the thread that holds
# the GIL. Holding the GIAC lock while waiting for the GIL, while another
# thread holds the GIL and waits for the GIAC lock, would deadlock. So neither
# conversion holds the GIAC lock while calling Python. Each runs in two passes
# over a small intermediate tree that is plain Julia data:
#
#   to_sympy:  GIAC -> tree   under the GIAC lock, no Python
#              tree -> Sym    Python only, lock released
#   to_giac:   Sym  -> tree   Python only, no GIAC
#              tree -> GIAC   under the GIAC lock, no Python
#
# Errors are carried in the tree and raised in the second pass, at the place
# the one-pass conversion raised them, so a failing conversion reports the same
# error as before.
# ============================================================================

# ============================================================================
# Core Conversion: GIAC -> SymPy
# ============================================================================

# Intermediate tree for to_sympy. A leaf is a number (an `Int64`, a `Float64` or a
# `BigInt`), which `Sym` converts.
struct _Idnt
    name::String
end
struct _Call
    op::String
    args::Vector{Any}
end
struct _Cplx
    re::Any
    im::Any
end
struct _Frac
    num::Any
    den::Any
end
struct _Fail
    msg::String
end

"""
    _gen_to_tree(gen) -> tree

First pass of `to_sympy`: read a CxxWrap Gen object tree into plain Julia data.
The caller holds the GIAC lock. Makes no Python call.
"""
function _gen_to_tree(gen)
    t = Giac.GenTypes.T(Giac.GiacCxxBindings.type(gen))

    if t == Giac.GenTypes.INT
        return Giac.GiacCxxBindings.to_int64(gen)

    elseif t == Giac.GenTypes.DOUBLE
        return Giac.GiacCxxBindings.to_double(gen)

    elseif t == Giac.GenTypes.ZINT
        # Arbitrary precision integer: round-trip through GiacExpr/to_julia,
        # which parses the GMP-backed decimal string into a BigInt.
        sub = GiacExpr(Giac._gen_to_ptr(gen))
        return Giac.to_julia(sub)::BigInt

    elseif t == Giac.GenTypes.CPLX
        return _Cplx(_gen_to_tree(Giac.GiacCxxBindings.cplx_re(gen)),
                     _gen_to_tree(Giac.GiacCxxBindings.cplx_im(gen)))

    elseif t == Giac.GenTypes.IDNT
        return _Idnt(String(Giac.GiacCxxBindings.idnt_name(gen)))

    elseif t == Giac.GenTypes.SYMB
        op = String(Giac.GiacCxxBindings.symb_sommet_name(gen))
        feuille = Giac.GiacCxxBindings.symb_feuille(gen)
        ftype = Giac.GenTypes.T(Giac.GiacCxxBindings.type(feuille))

        args = if ftype == Giac.GenTypes.VECT
            n = Giac.GiacCxxBindings.vect_size(feuille)
            [Giac.GiacCxxBindings.vect_at(feuille, i - 1) for i in 1:n]
        else
            [feuille]
        end
        return _Call(op, Any[_gen_to_tree(a) for a in args])

    elseif t == Giac.GenTypes.FRAC
        return _Frac(_gen_to_tree(Giac.GiacCxxBindings.frac_num(gen)),
                     _gen_to_tree(Giac.GiacCxxBindings.frac_den(gen)))

    elseif t == Giac.GenTypes.STRNG
        return _Fail("Cannot convert GIAC string to SymPy.Sym")

    else
        return _Fail("Unsupported GIAC type '$(t)' (code $(Int(t))) in to_sympy conversion")
    end
end

"""
    _tree_to_sympy(node, var_cache::Dict{String, Sym}) -> Sym

Second pass of `to_sympy`: build the SymPy.jl `Sym` expression. Makes no GIAC
call, so it runs without the GIAC lock. Mirrors
`GiacSymbolicsExt._gen_tree_to_symbolics` but produces SymPy objects.
"""
_tree_to_sympy(x::Number, var_cache::Dict{String, Sym}) = Sym(x)

_tree_to_sympy(f::_Fail, var_cache::Dict{String, Sym}) = error(f.msg)

function _tree_to_sympy(c::_Cplx, var_cache::Dict{String, Sym})
    re = _tree_to_sympy(c.re, var_cache)
    im = _tree_to_sympy(c.im, var_cache)
    return re + im * SymPy.IM
end

function _tree_to_sympy(f::_Frac, var_cache::Dict{String, Sym})
    num = _tree_to_sympy(f.num, var_cache)
    den = _tree_to_sympy(f.den, var_cache)
    return num / den
end

function _tree_to_sympy(id::_Idnt, var_cache::Dict{String, Sym})
    name = id.name
    if name == "pi" || name == "π"
        return SymPy.PI
    elseif name == "i"
        return SymPy.IM
    elseif name == "e"
        return SymPy.E
    end
    if !haskey(var_cache, name)
        var_cache[name] = SymPy.symbols(name)
    end
    return var_cache[name]
end

function _tree_to_sympy(c::_Call, var_cache::Dict{String, Sym})
    op = c.op
    converted = Sym[_tree_to_sympy(a, var_cache) for a in c.args]

    if op == "+"
        return reduce(+, converted)
    elseif op == "*"
        return reduce(*, converted)
    elseif op == "-"
        return length(converted) == 1 ? -converted[1] : converted[1] - converted[2]
    elseif op == "/"
        return converted[1] / converted[2]
    elseif op == "^"
        return converted[1] ^ converted[2]
    elseif op == "inv"
        # GIAC reciprocal operator (e.g. 1/ln(10) inside log10(x)).
        # Build Sym(1)/arg explicitly so constants stay symbolic instead
        # of relying on Base.inv being overloaded on Sym.
        return Sym(1) / converted[1]
    else
        func = _get_julia_function(op)
        if func === nothing
            error("Unsupported GIAC operator '$op' in to_sympy conversion")
        end
        return func(converted...)
    end
end

# ============================================================================
# Public API
# ============================================================================

"""
    Giac.to_sympy(expr::GiacExpr)

Convert a GiacExpr to a SymPy.jl (`SymPy.Sym`) expression.

Preserves symbolic mathematical functions (`sin`, `cos`, `exp`, `sqrt`, `log`,
…) instead of evaluating them numerically, and maps GIAC constants to their
SymPy counterparts (`pi` -> `SymPy.PI`, `e` -> `SymPy.E`, `i` -> `SymPy.IM`).

# Example
```julia
using Giac, SymPy
result = giac_eval("sin(x) + ln(y)")
sym_expr = to_sympy(result)  # sin(symbols("x")) + log(symbols("y"))
```
"""
function Giac.to_sympy(expr::GiacExpr)
    # GIAC side under the GIAC lock, Python side after it is released
    tree = GC.@preserve expr Giac.with_giac_lock() do
        _gen_to_tree(Giac._ptr_to_gen(expr))
    end
    return _tree_to_sympy(tree, Dict{String, Sym}())
end

# ============================================================================
# SymPy to Giac direction (to_giac(::Sym))
# ============================================================================

"""
    SYMPY_TO_GIAC_NAME

Dictionary mapping SymPy class names to GIAC operator names where they differ.
For names that match exactly (`sin`, `cos`, `exp`, `tan`, …) the SymPy class
name is used directly.
"""
const SYMPY_TO_GIAC_NAME = Dict{String, String}(
    "log" => "ln",  # SymPy "log" <-> GIAC "ln" (natural logarithm)
)

"""
    _bigint_to_gen(n::BigInt) -> Gen

Convert a Julia `BigInt` to a GIAC `Gen` using direct GMP binary transfer.
Mirrors `GiacSymbolicsExt._bigint_to_gen`. The caller holds the GIAC lock.
"""
function _bigint_to_gen(n::BigInt)
    if n == 0
        return Giac.GiacCxxBindings.Gen(Int32(0))
    end
    n_sign = Int32(Base.sign(n))
    abs_n = abs(n)
    bit_count = ccall((:__gmpz_sizeinbase, Base.GMP.libgmp), Csize_t,
                      (Ref{BigInt}, Cint), abs_n, 2)
    byte_count = div(bit_count + 7, 8)
    bytes = Vector{UInt8}(undef, byte_count)
    actual_count = Ref{Csize_t}(0)
    ccall((:__gmpz_export, Base.GMP.libgmp), Ptr{Cvoid},
          (Ptr{UInt8}, Ref{Csize_t}, Cint, Csize_t, Cint, Csize_t, Ref{BigInt}),
          bytes, actual_count, 1, 1, 1, 0, abs_n)
    if actual_count[] < byte_count
        resize!(bytes, actual_count[])
    end
    std_bytes = StdVector{UInt8}(bytes)
    return Giac.GiacCxxBindings.make_zint_from_bytes(std_bytes, n_sign)
end

"""
    _pyclass(ex::Sym) -> String

Return the SymPy (Python) class name of `ex`, e.g. `"Add"`, `"Mul"`, `"Pow"`,
`"Symbol"`, `"Integer"`, `"sin"`, `"Pi"`.
"""
@inline _pyclass(ex::Sym) = ex.o[:__class__][:__name__]

# Intermediate tree for to_giac(::Sym). A leaf is an `Int32` (a GIAC `_INT_`),
# a `BigInt` or a `Float64`; `_Idnt`, `_Cplx` and `_Frac` are shared with the
# other direction. `_Symb` is a GIAC symbolic built without evaluation.
struct _Symb
    op::String
    args::Vector{Any}
end

"""
    _sympy_to_tree(ex) -> tree

First pass of `to_giac(::Sym)`: read a SymPy `Sym` expression tree into plain
Julia data. Makes Python calls only, so it runs without the GIAC lock.
"""
function _sympy_to_tree(ex)
    cls = _pyclass(ex)

    if cls == "Integer"
        return convert(BigInt, ex)

    elseif cls == "Zero"
        return Int32(0)
    elseif cls == "One"
        return Int32(1)
    elseif cls == "NegativeOne"
        return Int32(-1)
    elseif cls == "Half"
        return _Frac(Int32(1), Int32(2))

    elseif cls == "Float"
        return Float64(convert(Float64, ex))

    elseif cls == "Rational"
        return _Frac(convert(BigInt, ex.p), convert(BigInt, ex.q))

    elseif cls == "Symbol"
        return _Idnt(string(ex.name))

    elseif cls == "Pi"
        return _Idnt("pi")

    elseif cls == "Exp1"
        return _Idnt("e")

    elseif cls == "ImaginaryUnit"
        # Build the actual GIAC complex 0+1*i rather than a bare identifier,
        # so arithmetic like 4*I combines into 4*i instead of a malformed
        # identifier product.
        return _Cplx(Int32(0), Int32(1))

    elseif cls == "Add" || cls == "Mul"
        op = (cls == "Add") ? "+" : "*"
        args = ex.args
        if length(args) == 1
            return _sympy_to_tree(args[1])
        end
        return _Symb(op, Any[_sympy_to_tree(a) for a in args])

    elseif cls == "Pow"
        args = ex.args
        base = _sympy_to_tree(args[1])
        exp = args[2]
        # SymPy represents sqrt(x) as Pow(x, 1/2); rebuild as GIAC sqrt(x).
        # The exponent may be the singleton "Half" class or a generic
        # "Rational" equal to 1/2.
        ecls = _pyclass(exp)
        if (ecls == "Half") ||
           (ecls == "Rational" &&
            convert(BigInt, exp.p) == 1 && convert(BigInt, exp.q) == 2)
            return _Symb("sqrt", Any[base])
        end
        return _Symb("^", Any[base, _sympy_to_tree(exp)])

    else
        # Generic function call: sin, cos, tan, exp, log, ... — map the name
        # (e.g. log -> ln) and rebuild as a GIAC symbolic.
        giac_name = get(SYMPY_TO_GIAC_NAME, cls, cls)
        return _Symb(giac_name, Any[_sympy_to_tree(a) for a in ex.args])
    end
end

"""
    _tree_to_gen(node) -> Gen

Second pass of `to_giac(::Sym)`: build the GIAC `Gen` by direct C++
construction (no string serialization). The caller holds the GIAC lock. Makes
no Python call. Mirrors `GiacSymbolicsExt._convert_to_gen`.
"""
_tree_to_gen(n::Int32) = Giac.GiacCxxBindings.Gen(n)
_tree_to_gen(n::BigInt) = _bigint_to_gen(n)
_tree_to_gen(x::Float64) = Giac.GiacCxxBindings.Gen(x)
_tree_to_gen(id::_Idnt) = Giac.GiacCxxBindings.make_identifier(id.name)
_tree_to_gen(f::_Frac) =
    Giac.GiacCxxBindings.make_fraction(_tree_to_gen(f.num), _tree_to_gen(f.den))
_tree_to_gen(c::_Cplx) =
    Giac.GiacCxxBindings.make_complex(_tree_to_gen(c.re), _tree_to_gen(c.im))
function _tree_to_gen(s::_Symb)
    gen_args = Giac.GiacCxxBindings.Gen[_tree_to_gen(a) for a in s.args]
    return Giac.GiacCxxBindings.make_symbolic_unevaluated(
        s.op, StdVector{Giac.GiacCxxBindings.Gen}(gen_args))
end

"""
    Giac.to_giac(expr::Sym)

Convert a SymPy.jl (`SymPy.Sym`) expression to a `GiacExpr`.

Uses direct C++ Gen construction (no string serialization). Maps SymPy
constants to their GIAC counterparts (`SymPy.PI` -> `pi`, `SymPy.E` -> `e`,
`SymPy.IM` -> `i`), and `log` to GIAC `ln`. SymPy's `sqrt(x)` (internally
`Pow(x, 1/2)`) is rebuilt as GIAC `sqrt(x)`.

# Example
```julia
using Giac, SymPy
x = symbols("x")
giac_expr = to_giac(sin(x) + log(x))  # GiacExpr: sin(x)+ln(x)
```
"""
function Giac.to_giac(expr::Sym)::GiacExpr
    # Python side first, without the GIAC lock; then the GIAC side under it
    tree = _sympy_to_tree(expr)
    return Giac.with_giac_lock() do
        GiacExpr(Giac._gen_to_ptr(_tree_to_gen(tree)))
    end
end

"""
    Giac.to_giac(m::AbstractArray{<:Sym})

Refuse non-scalar SymPy matrices: the bridge is scalar-only. Throws an
`ErrorException`.
"""
function Giac.to_giac(m::AbstractArray{<:Sym})
    error("to_giac(::AbstractArray{<:SymPy.Sym}) is not supported: " *
          "the SymPy bridge is scalar-only")
end

export to_sympy, to_giac

end # module GiacSymPyExt
