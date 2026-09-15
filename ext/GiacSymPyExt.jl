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
# Core Conversion
# ============================================================================

"""
    _gen_to_sympy(gen, var_cache::Dict{String, Sym}) -> Sym

Recursively convert a CxxWrap Gen object tree to a SymPy.jl `Sym` expression.
Mirrors `GiacSymbolicsExt._gen_tree_to_symbolics` but produces SymPy objects.
"""
function _gen_to_sympy(gen, var_cache::Dict{String, Sym})
    t = Giac.GenTypes.T(Giac.GiacCxxBindings.type(gen))

    if t == Giac.GenTypes.INT
        return Sym(Giac.GiacCxxBindings.to_int64(gen))

    elseif t == Giac.GenTypes.DOUBLE
        return Sym(Giac.GiacCxxBindings.to_double(gen))

    elseif t == Giac.GenTypes.ZINT
        # Arbitrary precision integer: round-trip through GiacExpr/to_julia,
        # which parses the GMP-backed decimal string into a BigInt.
        sub = GiacExpr(Giac._gen_to_ptr(gen))
        return Sym(Giac.to_julia(sub)::BigInt)

    elseif t == Giac.GenTypes.CPLX
        re = _gen_to_sympy(Giac.GiacCxxBindings.cplx_re(gen), var_cache)
        im = _gen_to_sympy(Giac.GiacCxxBindings.cplx_im(gen), var_cache)
        return re + im * SymPy.IM

    elseif t == Giac.GenTypes.IDNT
        name = String(Giac.GiacCxxBindings.idnt_name(gen))
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

        converted = Sym[_gen_to_sympy(a, var_cache) for a in args]

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

    elseif t == Giac.GenTypes.FRAC
        num = _gen_to_sympy(Giac.GiacCxxBindings.frac_num(gen), var_cache)
        den = _gen_to_sympy(Giac.GiacCxxBindings.frac_den(gen), var_cache)
        return num / den

    elseif t == Giac.GenTypes.STRNG
        error("Cannot convert GIAC string to SymPy.Sym")

    else
        error("Unsupported GIAC type '$(t)' (code $(Int(t))) in to_sympy conversion")
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
    var_cache = Dict{String, Sym}()
    gen = Giac._ptr_to_gen(expr)
    return _gen_to_sympy(gen, var_cache)
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
Mirrors `GiacSymbolicsExt._bigint_to_gen`.
"""
function _bigint_to_gen(n::BigInt)
    if n == 0
        return Giac.GiacCxxBindings.Gen(Int32(0))
    end
    n_sign = Int32(Base.sign(n))
    abs_n = abs(n)
    bit_count = ccall((:__gmpz_sizeinbase, :libgmp), Csize_t,
                      (Ref{BigInt}, Cint), abs_n, 2)
    byte_count = div(bit_count + 7, 8)
    bytes = Vector{UInt8}(undef, byte_count)
    actual_count = Ref{Csize_t}(0)
    ccall((:__gmpz_export, :libgmp), Ptr{Cvoid},
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

"""
    _sympy_to_gen(ex) -> Gen

Recursively convert a SymPy `Sym` expression tree to a GIAC `Gen` using direct
C++ construction (no string serialization). Mirrors
`GiacSymbolicsExt._convert_to_gen`.
"""
function _sympy_to_gen(ex)
    cls = _pyclass(ex)

    if cls == "Integer"
        return _bigint_to_gen(convert(BigInt, ex))

    elseif cls == "Zero"
        return Giac.GiacCxxBindings.Gen(Int32(0))
    elseif cls == "One"
        return Giac.GiacCxxBindings.Gen(Int32(1))
    elseif cls == "NegativeOne"
        return Giac.GiacCxxBindings.Gen(Int32(-1))
    elseif cls == "Half"
        return Giac.GiacCxxBindings.make_fraction(
            Giac.GiacCxxBindings.Gen(Int32(1)),
            Giac.GiacCxxBindings.Gen(Int32(2)))

    elseif cls == "Float"
        return Giac.GiacCxxBindings.Gen(Float64(convert(Float64, ex)))

    elseif cls == "Rational"
        num = _bigint_to_gen(convert(BigInt, ex.p))
        den = _bigint_to_gen(convert(BigInt, ex.q))
        return Giac.GiacCxxBindings.make_fraction(num, den)

    elseif cls == "Symbol"
        return Giac.GiacCxxBindings.make_identifier(string(ex.name))

    elseif cls == "Pi"
        return Giac.GiacCxxBindings.make_identifier("pi")

    elseif cls == "Exp1"
        return Giac.GiacCxxBindings.make_identifier("e")

    elseif cls == "ImaginaryUnit"
        # Build the actual GIAC complex 0+1*i rather than a bare identifier,
        # so arithmetic like 4*I combines into 4*i instead of a malformed
        # identifier product.
        return Giac.GiacCxxBindings.make_complex(
            Giac.GiacCxxBindings.Gen(Int32(0)),
            Giac.GiacCxxBindings.Gen(Int32(1)))

    elseif cls == "Add" || cls == "Mul"
        op = (cls == "Add") ? "+" : "*"
        args = ex.args
        if length(args) == 1
            return _sympy_to_gen(args[1])
        end
        gen_args = Giac.GiacCxxBindings.Gen[_sympy_to_gen(a) for a in args]
        return Giac.GiacCxxBindings.make_symbolic_unevaluated(
            op, StdVector{Giac.GiacCxxBindings.Gen}(gen_args))

    elseif cls == "Pow"
        args = ex.args
        base = _sympy_to_gen(args[1])
        exp = args[2]
        # SymPy represents sqrt(x) as Pow(x, 1/2); rebuild as GIAC sqrt(x).
        # The exponent may be the singleton "Half" class or a generic
        # "Rational" equal to 1/2.
        ecls = _pyclass(exp)
        if (ecls == "Half") ||
           (ecls == "Rational" &&
            convert(BigInt, exp.p) == 1 && convert(BigInt, exp.q) == 2)
            return Giac.GiacCxxBindings.make_symbolic_unevaluated(
                "sqrt", StdVector{Giac.GiacCxxBindings.Gen}([base]))
        end
        exp_gen = _sympy_to_gen(exp)
        return Giac.GiacCxxBindings.make_symbolic_unevaluated(
            "^", StdVector{Giac.GiacCxxBindings.Gen}([base, exp_gen]))

    else
        # Generic function call: sin, cos, tan, exp, log, ... — map the name
        # (e.g. log -> ln) and rebuild as a GIAC symbolic.
        giac_name = get(SYMPY_TO_GIAC_NAME, cls, cls)
        args = ex.args
        gen_args = Giac.GiacCxxBindings.Gen[_sympy_to_gen(a) for a in args]
        return Giac.GiacCxxBindings.make_symbolic_unevaluated(
            giac_name, StdVector{Giac.GiacCxxBindings.Gen}(gen_args))
    end
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
    gen = _sympy_to_gen(expr)
    return GiacExpr(Giac._gen_to_ptr(gen))
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