# Extension module for Symbolics.jl integration
# Provides bidirectional conversion between GiacExpr and Symbolics.Num types
# Requires the GIAC C++ wrapper library

module GiacSymbolicsExt

using Giac
using Symbolics
using CxxWrap: StdVector
import Symbolics.SymbolicUtils: Sym, symtype, issym, iscall, operation, arguments, is_literal_number, unwrap_const

# ============================================================================
# GIAC to Julia Name Mapping
# Only needed for function names that differ between GIAC and Julia
# ============================================================================

"""
    GIAC_NAME_MAPPING

Dictionary mapping GIAC function names to Julia functions where names differ.
For functions with identical names, Julia functions are resolved dynamically.
"""
const GIAC_NAME_MAPPING = Dict{String, Function}(
    "ln" => log,  # GIAC uses "ln", Julia uses "log"
)

"""
    _get_julia_function(giac_name::String) -> Union{Function, Nothing}

Get the Julia function corresponding to a GIAC function name.
First checks GIAC_NAME_MAPPING for name differences, then tries to resolve
from Base using the same name. Returns nothing if not found.
"""
function _get_julia_function(giac_name::String)::Union{Function, Nothing}
    # Check name mapping first (for names that differ)
    if haskey(GIAC_NAME_MAPPING, giac_name)
        return GIAC_NAME_MAPPING[giac_name]
    end
    # Try to get function from Base with same name
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
# Julia to GIAC Name Mapping (reverse of GIAC_NAME_MAPPING)
# ============================================================================

"""
    JULIA_TO_GIAC_NAME

Dictionary mapping Julia functions to GIAC names where they differ.
Built from the reverse of GIAC_NAME_MAPPING. For functions with identical
names, the function name is used directly via nameof().
"""
const JULIA_TO_GIAC_NAME = Dict{Function, String}(
    v => k for (k, v) in GIAC_NAME_MAPPING
)

# ============================================================================
# Helper Functions
# ============================================================================

"""
    _bytes_to_bigint(bytes::Vector{UInt8}, sign::Int32) -> BigInt

Construct a BigInt from raw bytes and sign using direct GMP ccall.
"""
function _bytes_to_bigint(bytes::Vector{UInt8}, sign::Int32)::BigInt
    if isempty(bytes) || sign == 0
        return BigInt(0)
    end

    result = BigInt()
    ccall((:__gmpz_import, Base.GMP.libgmp), Cvoid,
          (Ref{BigInt}, Csize_t, Cint, Csize_t, Cint, Csize_t, Ptr{UInt8}),
          result, length(bytes), 1, 1, 1, 0, bytes)

    if sign < 0
        ccall((:__gmpz_neg, Base.GMP.libgmp), Cvoid,
              (Ref{BigInt}, Ref{BigInt}), result, result)
    end

    return result
end

"""
    _bigint_to_gen(n::BigInt) -> Gen

Convert a Julia BigInt to a GIAC Gen using direct GMP binary transfer.
Uses make_zint_from_bytes for arbitrary precision integers.
"""
function _bigint_to_gen(n::BigInt)
    if n == 0
        return Giac.GiacCxxBindings.Gen(Int32(0))
    end

    # Get sign (-1, 0, or 1)
    n_sign = Int32(Base.sign(n))

    # Export absolute value to bytes using GMP
    abs_n = abs(n)

    # Calculate number of bytes needed
    # GMP stores in limbs, we need to figure out byte count
    # Using mpz_sizeinbase gives bit count, convert to bytes
    bit_count = ccall((:__gmpz_sizeinbase, Base.GMP.libgmp), Csize_t,
                      (Ref{BigInt}, Cint), abs_n, 2)
    byte_count = div(bit_count + 7, 8)

    # Allocate buffer and export
    bytes = Vector{UInt8}(undef, byte_count)
    actual_count = Ref{Csize_t}(0)
    ccall((:__gmpz_export, Base.GMP.libgmp), Ptr{Cvoid},
          (Ptr{UInt8}, Ref{Csize_t}, Cint, Csize_t, Cint, Csize_t, Ref{BigInt}),
          bytes, actual_count, 1, 1, 1, 0, abs_n)

    # Resize if needed (GMP may use fewer bytes)
    if actual_count[] < byte_count
        resize!(bytes, actual_count[])
    end

    # Convert to StdVector for C++ wrapper
    std_bytes = StdVector{UInt8}(bytes)

    return Giac.GiacCxxBindings.make_zint_from_bytes(std_bytes, n_sign)
end

"""
    _julia_to_giac_op(op) -> String

Get the GIAC operator/function name for a Julia function.
First checks JULIA_TO_GIAC_NAME for names that differ, then uses nameof().
"""
function _julia_to_giac_op(op)::String
    # Check if this function has a different name in GIAC
    if haskey(JULIA_TO_GIAC_NAME, op)
        return JULIA_TO_GIAC_NAME[op]
    end
    # Use the function name directly (works for operators like +, -, *, / and same-name functions)
    return string(nameof(op))
end

# ============================================================================
# Direct Symbolics to Gen Conversion
# ============================================================================

"""
    _convert_to_gen(expr) -> Gen

Recursively convert a Symbolics.jl expression tree to a GIAC Gen object.
This is the core function for direct to_giac conversion without string serialization.
"""
function _convert_to_gen(expr)
    # Unwrap Num if needed
    unwrapped = expr isa Num ? Symbolics.unwrap(expr) : expr

    # Handle numeric literals
    if unwrapped isa Integer
        if unwrapped isa BigInt
            return _bigint_to_gen(unwrapped)
        elseif typemin(Int32) <= unwrapped <= typemax(Int32)
            # Small integer - use Gen(Int32) constructor to preserve _INT_ type
            # Note: CxxWrap bundles Int64 with Float64, so we must use Int32
            return Giac.GiacCxxBindings.Gen(Int32(unwrapped))
        else
            # Medium-size integer that doesn't fit Int32 - use string constructor
            return Giac.GiacCxxBindings.Gen(string(unwrapped))
        end
    elseif unwrapped isa AbstractFloat
        return Giac.GiacCxxBindings.Gen(Float64(unwrapped))
    elseif unwrapped isa Rational
        num_gen = _convert_to_gen(numerator(unwrapped))
        den_gen = _convert_to_gen(denominator(unwrapped))
        return Giac.GiacCxxBindings.make_fraction(num_gen, den_gen)
    elseif unwrapped isa Complex
        re_gen = _convert_to_gen(real(unwrapped))
        im_gen = _convert_to_gen(imag(unwrapped))
        return Giac.GiacCxxBindings.make_complex(re_gen, im_gen)
    end

    # Handle symbolic literal numbers (e.g., integer exponents in Symbolics v7)
    if is_literal_number(unwrapped)
        return _convert_to_gen(unwrap_const(unwrapped))
    end

    # Handle symbolic variables (identifiers)
    if issym(unwrapped)
        name = String(Symbolics.tosymbol(unwrapped))
        return Giac.GiacCxxBindings.make_identifier(name)
    end

    # Handle function calls / compound expressions
    if iscall(unwrapped)
        op = operation(unwrapped)
        args = arguments(unwrapped)

        # Convert all arguments recursively
        gen_args = [_convert_to_gen(a) for a in args]

        # Get GIAC operator/function name (handles log->ln mapping automatically)
        giac_op = _julia_to_giac_op(op)

        # Use make_symbolic_unevaluated to build expression without evaluation
        args_vec = StdVector{Giac.GiacCxxBindings.Gen}(gen_args)
        return Giac.GiacCxxBindings.make_symbolic_unevaluated(giac_op, args_vec)
    end

    # Handle special constants
    if unwrapped === π || unwrapped === Base.MathConstants.pi
        return Giac.GiacCxxBindings.make_identifier("pi")
    elseif unwrapped === ℯ || unwrapped === Base.MathConstants.e
        return Giac.GiacCxxBindings.make_identifier("e")
    elseif unwrapped === im
        return Giac.GiacCxxBindings.make_identifier("i")
    end

    # Fallback error
    error("Cannot convert expression of type $(typeof(unwrapped)) to GIAC Gen")
end

# ============================================================================
# Core Conversion Functions
# ============================================================================

"""
    _gen_tree_to_symbolics(gen, var_cache::Dict{String, Num}) -> Any

Recursively convert a CxxWrap Gen object tree to Symbolics.jl expression.
Uses Symbolics.term() for multiplication and exponentiation to preserve factored structure.
"""
function _gen_tree_to_symbolics(gen, var_cache::Dict{String, Num})
    t = Giac.GenTypes.T(Giac.GiacCxxBindings.type(gen))

    if t == Giac.GenTypes.INT
        return Num(Giac.GiacCxxBindings.to_int64(gen))

    elseif t == Giac.GenTypes.DOUBLE
        return Num(Giac.GiacCxxBindings.to_double(gen))

    elseif t == Giac.GenTypes.ZINT
        # Arbitrary precision integer via direct GMP binary transfer
        bytes = Vector{UInt8}(Giac.GiacCxxBindings.zint_to_bytes(gen))
        sign = Int32(Giac.GiacCxxBindings.zint_sign(gen))
        return Num(_bytes_to_bigint(bytes, sign))

    elseif t == Giac.GenTypes.CPLX
        # Complex number via direct C++ accessors
        re_gen = Giac.GiacCxxBindings.cplx_re(gen)
        im_gen = Giac.GiacCxxBindings.cplx_im(gen)
        re_sym = _gen_tree_to_symbolics(re_gen, var_cache)
        im_sym = _gen_tree_to_symbolics(im_gen, var_cache)
        return re_sym + im_sym * im

    elseif t == Giac.GenTypes.IDNT
        name = String(Giac.GiacCxxBindings.idnt_name(gen))
        # Handle special constants
        if name == "pi" || name == "π"
            return Symbolics.pi
        elseif name == "i"
            return im
        end
        # Create or retrieve symbolic variable
        if !haskey(var_cache, name)
            var_cache[name] = Symbolics.variable(Symbol(name))
        end
        return var_cache[name]

    elseif t == Giac.GenTypes.SYMB
        op = String(Giac.GiacCxxBindings.symb_sommet_name(gen))
        feuille = Giac.GiacCxxBindings.symb_feuille(gen)
        feuille_type = Giac.GenTypes.T(Giac.GiacCxxBindings.type(feuille))

        # Get arguments
        args = if feuille_type == Giac.GenTypes.VECT
            n = Giac.GiacCxxBindings.vect_size(feuille)
            [Giac.GiacCxxBindings.vect_at(feuille, i-1) for i in 1:n]
        else
            [feuille]
        end

        # Recursively convert arguments — ensure all are Num for consistent arithmetic
        converted_args = map(args) do a
            result = _gen_tree_to_symbolics(a, var_cache)
            result isa Num ? result : Symbolics.wrap(result)
        end

        # Handle operators - use Symbolics.term() for * and ^ to preserve symbolic structure
        # (e.g., sqrt(2) stays symbolic instead of evaluating to 1.414...)
        if op == "*"
            unwrapped = [Symbolics.unwrap(a) for a in converted_args]
            # Pairwise term() to avoid 3+ arg term() which breaks Symbolics.wrap()
            result = unwrapped[1]
            for i in 2:length(unwrapped)
                result = Symbolics.term(*, result, unwrapped[i])
            end
            return Symbolics.wrap(result)
        elseif op == "^"
            unwrapped = [Symbolics.unwrap(a) for a in converted_args]
            return Symbolics.wrap(Symbolics.term(^, unwrapped...))
        elseif op == "+"
            return reduce(+, converted_args)
        elseif op == "-"
            if length(converted_args) == 1
                return -converted_args[1]
            else
                return converted_args[1] - converted_args[2]
            end
        elseif op == "/"
            return converted_args[1] / converted_args[2]
        else
            # Try to resolve as a Julia function — use term() to preserve symbolic form
            julia_func = _get_julia_function(op)
            if julia_func !== nothing
                unwrapped = [Symbolics.unwrap(a) for a in converted_args]
                return Symbolics.wrap(Symbolics.term(julia_func, unwrapped...))
            else
                error("Unsupported GIAC operator '$op' in to_symbolics conversion")
            end
        end

    elseif t == Giac.GenTypes.VECT
        n = Giac.GiacCxxBindings.vect_size(gen)
        return [_gen_tree_to_symbolics(Giac.GiacCxxBindings.vect_at(gen, i-1), var_cache) for i in 1:n]

    elseif t == Giac.GenTypes.FRAC
        num = Giac.GiacCxxBindings.frac_num(gen)
        den = Giac.GiacCxxBindings.frac_den(gen)
        num_sym = _gen_tree_to_symbolics(num, var_cache)
        den_sym = _gen_tree_to_symbolics(den, var_cache)
        return num_sym // den_sym

    else
        error("Unsupported GIAC type '$(t)' (code $(Int(t))) in to_symbolics conversion")
    end
end

# ============================================================================
# Public API Functions
# ============================================================================

"""
    to_giac(expr::Num)

Convert a Symbolics.jl expression to a GiacExpr.

Uses direct tree traversal and C++ Gen construction functions for efficient
conversion without string serialization.

# Example
```julia
using Giac, Symbolics
@variables x y
giac_expr = to_giac(x^2 + y)
```
"""
function Giac.to_giac(expr::Num)::GiacExpr
    # Use direct conversion via tree traversal to build Gen
    gen = _convert_to_gen(expr)
    # Convert Gen directly to GiacExpr without string serialization
    ptr = Giac._gen_to_ptr(gen)
    return GiacExpr(ptr)
end

"""
    to_symbolics(expr::GiacExpr)

Convert a GiacExpr to a Symbolics.jl Num expression.

Preserves symbolic mathematical functions like sqrt, exp, log, sin, cos, etc.
instead of evaluating them to floating-point approximations.

Also preserves factorized expression structure:
- `ifactor(n) |> to_symbolics` returns factored form (e.g., `2^6*5^6`)
- `factor(poly) |> to_symbolics` returns factored polynomial form

# Examples
```julia
using Giac, Symbolics
using Giac.Commands: ifactor, factor

# sqrt(2) is preserved symbolically
result = giac_eval("sqrt(2)")
sym_expr = to_symbolics(result)  # sqrt(2), not 1.414...

# Integer factorization is preserved
result = ifactor(1000000)
sym_expr = to_symbolics(result)  # 2^6*5^6, not 1000000

# Polynomial factorization is preserved
x = giac_eval("x")
result = factor(x^2 - 1)
sym_expr = to_symbolics(result)  # (x-1)*(x+1)
```
"""
function Giac.to_symbolics(expr::GiacExpr)
    var_cache = Dict{String, Num}()
    # Feature 052: Direct pointer conversion without string serialization
    # Use _ptr_to_gen to get Gen directly from the GiacExpr pointer
    gen = Giac._ptr_to_gen(expr)
    result = _gen_tree_to_symbolics(gen, var_cache)
    return result
end

# Export conversion functions
export to_giac, to_symbolics

# ============================================================================
# build_function — Symbolics backend (Tier 3, 067-build-function-tier3)
# ============================================================================
#
# When this extension is loaded, override the internal hook
# Giac._build_function_symbolics_impl so that `Giac.build_function(expr,
# vars...; backend = :symbolics)` round-trips through `to_symbolics` and
# compiles via `Symbolics.build_function`, returning a native Julia callable
# that is autodiff-friendly and faster in hot loops.
#
# Naming caveat: `Symbolics` also exports `build_function`. When both
# `using Giac` and `using Symbolics` are in scope, the bare name is ambiguous
# and Julia raises UndefVarError. Users must qualify as
# `Giac.build_function(...)` (or `Symbolics.build_function(...)`). Documented
# in the docstring and docs/src/julia_functions.md.

function Giac._build_function_symbolics_impl(expr::Giac.GiacExpr,
                                              vars::Tuple{Vararg{Giac.GiacExpr}})
    # Round-trip through Symbolics.
    sym_expr = Giac.to_symbolics(expr)
    sym_vars = map(Giac.to_symbolics, vars)

    # Free-symbol check (contract clause B6). Every symbolic variable that
    # appears in the expression must also appear in the bound vars.
    expr_vars  = Set(Symbolics.get_variables(sym_expr))
    bound_vars = Set{Any}()
    for sv in sym_vars
        for v in Symbolics.get_variables(sv)
            push!(bound_vars, v)
        end
    end
    free = setdiff(expr_vars, bound_vars)
    if !isempty(free)
        names = join(string.(collect(free)), ", ")
        throw(ArgumentError(
            "expression contains free symbol(s) [$names] not bound by the " *
            "vars argument; either bind them as additional vars or use " *
            "backend = :giac, which leaves them as a residual GiacExpr."))
    end

    # Zero-vars constant case: return a 0-arg closure that evaluates the
    # constant once. Avoids version-dependent behavior of
    # Symbolics.build_function on no-arg input.
    if isempty(vars)
        v = Symbolics.value(sym_expr)
        return () -> v
    end

    # Generate the compiled callable. expression = Val{false} returns a
    # RuntimeGeneratedFunction (world-age safe).
    return Symbolics.build_function(sym_expr, sym_vars...; expression = Val{false})
end

end # module GiacSymbolicsExt
