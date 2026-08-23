# Extension module for SymPy.jl integration
# Provides GiacExpr -> SymPy.Sym conversion (to_sympy).
# Requires the GIAC C++ wrapper library
#
# Feature 080-sympy-bridge: bidirectional bridge between Giac.jl and SymPy.jl.
# This module currently implements the Giac -> SymPy direction via
# `Giac.to_sympy(::GiacExpr)`. The reverse direction
# (`Giac.to_giac(::SymPy.Sym)`) is tracked separately.

module GiacSymPyExt

using Giac
using SymPy

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

export to_sympy

end # module GiacSymPyExt