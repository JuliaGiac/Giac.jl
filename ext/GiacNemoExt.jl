# ---------------------------------------------------------------------------
# GiacNemoExt — the Nemo.jl bridge.
#
# Loaded only when `Nemo` is loaded alongside `Giac`. Bidirectional:
#
#   outward  Nemo -> Giac   Giac.to_giac(e::Nemo.RingElem)
#   inward   Giac -> Nemo   Giac.to_nemo(e::GiacExpr, parent::NemoRing)
#
# The inward direction takes a *parent ring*: Nemo elements are parent-typed
# (there is no free "Nemo integer", only `ZZ(42)`, `QQ(42)`, an element of a
# specific polynomial ring, ...), whereas a GiacExpr is untyped/symbolic. The
# caller therefore states the destination:
#
#   to_nemo(giac_eval("x^2+1"), polynomial_ring(ZZ,"x")[1])
#   to_nemo(giac_eval("a^2+3"),  K)            # K = number_field(...)
#   to_nemo(giac_eval("t^2+1"),  F)            # F = finite_field(7,3,"t")
#
# CONTRACT — value-preserving and name-preserving; NOT representation-
# preserving. Compare round trips by value (`==`), never by `string`: Nemo
# polynomials are canonical (expanded, ring-sorted); a Giac factored form
# arrives in Nemo expanded. Variable *names* survive both crossings; term
# order does not.
#
# v1 scope — see docs/src/extensions/nemo.md for the full refusal list and
# limitations. In short:
#   * supported outward: ZZRingElem, QQFieldElem, univariate polys over
#     ZZ/QQ, FqFieldElem (prime & non-prime), AbsSimpleNumFieldElem,
#     ZZMatrix/QQMatrix.
#   * supported inward parent: ZZ, QQ, a univariate polynomial ring over
#     ZZ/QQ, an AbsSimpleNumField, an FqField, a ZZ/QQ MatSpace.
#   * refused (both directions): transcendental functions (sin, cos, exp,
#     ln, sqrt, log10, ...), the constants pi/e, real/complex balls
#     (ArbFieldElem/AcbFieldElem), p-adics (PadicFieldElem). Reals are
#     refused because silent precision loss via a printed decimal is exactly
#     the trap the LibPARI bridge warns about.
# ---------------------------------------------------------------------------

module GiacNemoExt

using Giac
using Giac.GenTypes
using Nemo
using Nemo: ZZ, QQ
import Nemo: PolyRing, MatSpace, PolyRingElem, MatElem
using CxxWrap: StdVector

const OUTWARD_SUPPORTED =
    "ZZRingElem, QQFieldElem, univariate polys over ZZ/QQ, FqFieldElem, " *
    "AbsSimpleNumFieldElem, ZZMatrix/QQMatrix"
const INWARD_SUPPORTED =
    "parent ring ZZ, QQ, a univariate polynomial ring over ZZ/QQ, an " *
    "AbsSimpleNumField, an FqField, or a ZZ/QQ MatSpace"

# Allowed GIAC operators inside an expression destined for an algebraic
# Nemo ring (polynomial / number field / finite field). Anything else
# (sin, cos, exp, ln, sqrt, log10, ...) is transcendental and refused.
const ALGEBRAIC_OPS = Set(["+", "-", "*", "/", "^", "inv", "neg", "unsigned_numeric"])

# ===========================================================================
# Helpers — BigInt <-> Gen (mirror GiacSymPyExt / GiacSymbolicsExt)
# ===========================================================================

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
    return Giac.GiacCxxBindings.make_zint_from_bytes(StdVector{UInt8}(bytes), n_sign)
end

# Build a Gen symbolic power gen_ident^k (gen^0 => 1, gen^1 => gen_ident).
function _gen_pow(gen_ident, k::Int)
    g = Giac.GiacCxxBindings
    if k == 0
        return g.Gen(Int32(1))
    elseif k == 1
        return gen_ident
    else
        return g.make_symbolic_unevaluated("^",
            StdVector{g.Gen}([gen_ident, g.Gen(Int32(k))]))
    end
end

# Build a symbolic product coeff * term (coeff^1 => coeff, term=1 => coeff).
function _gen_mul(coeff_gen, term_gen)
    g = Giac.GiacCxxBindings
    one_gen = g.Gen(Int32(1))
    if term_gen === one_gen || _is_one(term_gen)
        return coeff_gen
    end
    return g.make_symbolic_unevaluated("*",
        StdVector{g.Gen}([coeff_gen, term_gen]))
end

# Build a symbolic sum of the given Gen terms, dropping additive identities.
function _gen_sum(terms)
    g = Giac.GiacCxxBindings
    nonzero = filter(t -> !_is_zero(t), terms)
    isempty(nonzero) && return g.Gen(Int32(0))
    length(nonzero) == 1 && return nonzero[1]
    result = nonzero[1]
    for i in 2:length(nonzero)
        result = g.make_symbolic_unevaluated("+",
            StdVector{g.Gen}([result, nonzero[i]]))
    end
    return result
end

# Cheap structural zero/one test on a Gen, via Giac.to_julia (handles INT,
# ZINT and FRAC leaves uniformly).
function _gen_to_julia(gen)
    return Giac.to_julia(GiacExpr(Giac._gen_to_ptr(gen)))
end

function _is_zero(gen)
    t = GenTypes.T(Giac.GiacCxxBindings.type(gen))
    (t in (GenTypes.INT, GenTypes.ZINT, GenTypes.FRAC)) || return false
    return _gen_to_julia(gen) == 0
end

function _is_one(gen)
    t = GenTypes.T(Giac.GiacCxxBindings.type(gen))
    (t in (GenTypes.INT, GenTypes.ZINT, GenTypes.FRAC)) || return false
    return _gen_to_julia(gen) == 1
end

# ===========================================================================
# Outward: Nemo -> Giac
# ===========================================================================

"""
    Giac.to_giac(e::Nemo.ZZRingElem)

Convert a Nemo integer to a `GiacExpr` (ZINT for arbitrary precision).
"""
function Giac.to_giac(e::ZZRingElem)
    n = BigInt(e)
    if typemin(Int32) <= n <= typemax(Int32)
        return GiacExpr(Giac._gen_to_ptr(Giac.GiacCxxBindings.Gen(Int32(n))))
    end
    return GiacExpr(Giac._gen_to_ptr(_bigint_to_gen(n)))
end

"""
    Giac.to_giac(e::Nemo.QQFieldElem)

Convert a Nemo rational to a `GiacExpr` (GIAC fraction).
"""
function Giac.to_giac(e::QQFieldElem)
    g = Giac.GiacCxxBindings
    num = _bigint_to_gen(BigInt(numerator(e)))
    den = _bigint_to_gen(BigInt(denominator(e)))
    return GiacExpr(Giac._gen_to_ptr(g.make_fraction(num, den)))
end

"""
    Giac.to_giac(e::Nemo.UnivariatePolyRingElem)

Convert a univariate polynomial over ZZ or QQ to a `GiacExpr`, rebuilding it
as a symbolic sum of `c_k * var^k` terms. The variable name is taken from the
polynomial ring's generator.
"""
function Giac.to_giac(e::PolyRingElem)
    R = parent(e)
    vname = string(gen(R))
    gen_ident = Giac.GiacCxxBindings.make_identifier(vname)
    coeffs = collect(coefficients(e))   # low -> high
    terms = Giac.GiacCxxBindings.Gen[]
    for (k, c) in enumerate(coeffs)
        k0 = k - 1
        c_gen = Giac._ptr_to_gen(to_giac(c))
        term = _gen_pow(gen_ident, k0)
        push!(terms, _gen_mul(c_gen, term))
    end
    return GiacExpr(Giac._gen_to_ptr(_gen_sum(terms)))
end

"""
    Giac.to_giac(e::Nemo.FqFieldElem)

Convert a finite-field element to a `GiacExpr`. For a prime field (degree 1)
this is just the lifted integer; for a non-prime field it is a polynomial in
the field generator symbol.
"""
function Giac.to_giac(e::FqFieldElem)
    F = parent(e)
    d = Int(degree(F))
    vname = string(gen(F))
    gen_ident = Giac.GiacCxxBindings.make_identifier(vname)
    terms = Giac.GiacCxxBindings.Gen[]
    for k in 0:(d - 1)
        c = Nemo._coeff(e, k)            # ZZRingElem
        c_gen = Giac._ptr_to_gen(to_giac(c))
        term = _gen_pow(gen_ident, k)
        push!(terms, _gen_mul(c_gen, term))
    end
    return GiacExpr(Giac._gen_to_ptr(_gen_sum(terms)))
end

"""
    Giac.to_giac(e::Nemo.AbsSimpleNumFieldElem)

Convert a (absolute, simple) number-field element to a `GiacExpr`, rebuilding
it as a polynomial in the field generator symbol. The element is stored
mod its defining polynomial, so the result is already reduced.
"""
function Giac.to_giac(e::AbsSimpleNumFieldElem)
    K = parent(e)
    d = Int(degree(K))
    vname = string(gen(K))
    gen_ident = Giac.GiacCxxBindings.make_identifier(vname)
    terms = Giac.GiacCxxBindings.Gen[]
    for k in 0:(d - 1)
        c = Nemo.coeff(e, k)             # QQFieldElem
        c_gen = Giac._ptr_to_gen(to_giac(c))
        term = _gen_pow(gen_ident, k)
        push!(terms, _gen_mul(c_gen, term))
    end
    return GiacExpr(Giac._gen_to_ptr(_gen_sum(terms)))
end

"""
    Giac.to_giac(M::Nemo.ZZMatrix)
    Giac.to_giac(M::Nemo.QQMatrix)

Convert a Nemo matrix over ZZ or QQ to a `Giac.GiacMatrix`.
"""
function Giac.to_giac(M::MatElem)
    nr, nc = nrows(M), ncols(M)
    rows = Vector{Vector{GiacExpr}}()
    for i in 1:nr
        row = GiacExpr[to_giac(M[i, j]) for j in 1:nc]
        push!(rows, row)
    end
    return Giac.GiacMatrix(rows)
end

# Refusals — reals, balls, p-adics are out of scope in v1.
function Giac.to_giac(e::ArbFieldElem)
    error("to_giac(::$(typeof(e))) is not supported in v1: real balls are " *
          "refused to avoid silent precision loss. Supported: $OUTWARD_SUPPORTED")
end
function Giac.to_giac(e::AcbFieldElem)
    error("to_giac(::$(typeof(e))) is not supported in v1: complex balls are " *
          "refused to avoid silent precision loss. Supported: $OUTWARD_SUPPORTED")
end
function Giac.to_giac(e::PadicFieldElem)
    error("to_giac(::$(typeof(e))) is not supported: p-adic elements have no " *
          "Giac analogue. Supported: $OUTWARD_SUPPORTED")
end

# ===========================================================================
# Inward: Giac -> Nemo  (caller supplies the destination parent ring)
# ===========================================================================

# --- algebraic-guard: walk the Gen tree and refuse anything that is not
#     integer / rational / identifier / an algebraic operator. ---
function _assert_algebraic(gen)
    t = GenTypes.T(Giac.GiacCxxBindings.type(gen))
    if t in (GenTypes.INT, GenTypes.ZINT, GenTypes.FRAC)
        return
    elseif t == GenTypes.IDNT
        name = String(Giac.GiacCxxBindings.idnt_name(gen))
        if name == "pi" || name == "e"
            error("to_nemo: GIAC constant '$name' is transcendental and has " *
                  "no element in an algebraic Nemo ring. Supported: $INWARD_SUPPORTED")
        end
        return
    elseif t == GenTypes.DOUBLE || t == GenTypes.REAL
        error("to_nemo: real values are refused in v1 to avoid silent " *
              "precision loss. Supported: $INWARD_SUPPORTED")
    elseif t == GenTypes.STRNG
        error("to_nemo: GIAC strings have no Nemo analogue. Supported: $INWARD_SUPPORTED")
    elseif t == GenTypes.SYMB
        op = String(Giac.GiacCxxBindings.symb_sommet_name(gen))
        if !(op in ALGEBRAIC_OPS)
            error("to_nemo: GIAC operator '$op' is transcendental / " *
                  "unsupported in an algebraic Nemo ring. Supported: $INWARD_SUPPORTED")
        end
        feuille = Giac.GiacCxxBindings.symb_feuille(gen)
        ft = GenTypes.T(Giac.GiacCxxBindings.type(feuille))
        if ft == GenTypes.VECT
            n = Giac.GiacCxxBindings.vect_size(feuille)
            for i in 1:n
                _assert_algebraic(Giac.GiacCxxBindings.vect_at(feuille, i - 1))
            end
        else
            _assert_algebraic(feuille)
        end
        return
    elseif t == GenTypes.CPLX
        error("to_nemo: GIAC complex values have no algebraic Nemo ring " *
              "target in v1 (use number_field(x^2+1) explicitly). Supported: $INWARD_SUPPORTED")
    else
        error("to_nemo: unsupported GIAC type '$(t)'. Supported: $INWARD_SUPPORTED")
    end
end

# --- integer / rational leaf extraction via Giac.to_julia ---
function _leaf_to_julia(expr::GiacExpr)
    v = Giac.to_julia(expr)
    v isa Integer || v isa Rational ||
        error("to_nemo: expected an integer or rational value, got $(typeof(v)). " *
              "Supported: $INWARD_SUPPORTED")
    return v
end

# --- into ZZ ---
function Giac.to_nemo(expr::GiacExpr, ::ZZRing)
    gen = Giac._ptr_to_gen(expr)
    t = GenTypes.T(Giac.GiacCxxBindings.type(gen))
    if t in (GenTypes.DOUBLE, GenTypes.REAL)
        error("to_nemo: real values are refused in v1. Supported: $INWARD_SUPPORTED")
    elseif t == GenTypes.FRAC
        error("to_nemo: non-integer rational cannot be converted to ZZ. " *
              "Use QQ as the target. Supported: $INWARD_SUPPORTED")
    end
    v = Giac.to_julia(expr)
    v isa Integer ||
        error("to_nemo: expected an integer for ZZ target, got $(typeof(v)). " *
              "Supported: $INWARD_SUPPORTED")
    return ZZ(BigInt(v))
end

# --- into QQ ---
function Giac.to_nemo(expr::GiacExpr, ::QQField)
    gen = Giac._ptr_to_gen(expr)
    t = GenTypes.T(Giac.GiacCxxBindings.type(gen))
    if t in (GenTypes.DOUBLE, GenTypes.REAL)
        error("to_nemo: real values are refused in v1. Supported: $INWARD_SUPPORTED")
    end
    v = Giac.to_julia(expr)
    if v isa Integer
        return QQ(BigInt(v), BigInt(1))
    elseif v isa Rational
        return QQ(BigInt(numerator(v)), BigInt(denominator(v)))
    else
        error("to_nemo: expected an integer or rational for QQ target, got " *
              "$(typeof(v)). Supported: $INWARD_SUPPORTED")
    end
end

# --- into a univariate polynomial ring over ZZ or QQ ---
function Giac.to_nemo(expr::GiacExpr, R::PolyRing)
    gen = Giac._ptr_to_gen(expr)
    _assert_algebraic(gen)
    B = base_ring(R)
    vars = Giac.Commands.lvar(expr)
    nvars = length(vars)
    if nvars == 0
        return R(to_nemo(expr, B))
    elseif nvars == 1
        v = vars[1]
        d = Int(Giac.to_julia(Giac.Commands.degree(expr, v)))
        coeffs = [to_nemo(Giac.Commands.coeff(expr, v, k), B) for k in 0:d]
        return R(coeffs)
    else
        error("to_nemo: multivariate polynomials are not supported in v1 " *
              "(got $nvars free variables). Supported: $INWARD_SUPPORTED")
    end
end

# --- into an AbsSimpleNumField ---
function Giac.to_nemo(expr::GiacExpr, K::AbsSimpleNumField)
    gen = Giac._ptr_to_gen(expr)
    _assert_algebraic(gen)
    vars = Giac.Commands.lvar(expr)
    nvars = length(vars)
    if nvars == 0
        return K(to_nemo(expr, QQ))
    elseif nvars == 1
        v = vars[1]
        d = Int(Giac.to_julia(Giac.Commands.degree(expr, v)))
        coeffs = [to_nemo(Giac.Commands.coeff(expr, v, k), QQ) for k in 0:d]
        PQ = parent(defining_polynomial(K))    # QQ[x]
        return K(PQ(coeffs))
    else
        error("to_nemo: multivariate expressions are not supported into a " *
              "number field (got $nvars free variables). Supported: $INWARD_SUPPORTED")
    end
end

# --- into an FqField (prime or non-prime) ---
function Giac.to_nemo(expr::GiacExpr, F::FqField)
    gen = Giac._ptr_to_gen(expr)
    _assert_algebraic(gen)
    vars = Giac.Commands.lvar(expr)
    nvars = length(vars)
    if nvars == 0
        # constant -> lift to ZZ then into F
        v = Giac.to_julia(expr)
        v isa Integer ||
            error("to_nemo: expected an integer constant for a finite field, " *
                  "got $(typeof(v)). Supported: $INWARD_SUPPORTED")
        return F(ZZ(BigInt(v)))
    elseif nvars == 1
        v = vars[1]
        d = Int(Giac.to_julia(Giac.Commands.degree(expr, v)))
        # Build the element directly as a polynomial in the field generator.
        # (Going through polynomial_ring(F,"x")[1] and F(poly) does NOT map
        # x -> gen(F) for Fq fields — it applies an unrelated coercion that
        # yields wrong results.)
        t = Nemo.gen(F)
        result = Nemo.zero(F)
        for k in 0:d
            c = F(to_nemo(Giac.Commands.coeff(expr, v, k), ZZ))
            result += c * t^k
        end
        return result
    else
        error("to_nemo: multivariate expressions are not supported into a " *
              "finite field (got $nvars free variables). Supported: $INWARD_SUPPORTED")
    end
end

# --- into a ZZ/QQ MatSpace ---
function Giac.to_nemo(expr::GiacExpr, M::MatSpace)
    B = base_ring(M)
    nr = nrows(M)
    nc = ncols(M)
    # expr is a Giac VECT of VECTs (rows). Length-check the structure.
    length(expr) == nr ||
        error("to_nemo: matrix has $(length(expr)) rows, expected $nr.")
    elems = elem_type(B)[]
    for i in 1:nr
        row = expr[i]
        length(row) == nc ||
            error("to_nemo: row $i has $(length(row)) cols, expected $nc.")
        for j in 1:nc
            push!(elems, to_nemo(row[j], B))
        end
    end
    return matrix(B, nr, nc, elems)
end

export to_giac, to_nemo

end # module GiacNemoExt