# ---------------------------------------------------------------------------
# GiacLibPARIExt — the LibPARI.jl bridge.
#
# Loaded only when `LibPARI` is loaded alongside `Giac`. Giac.jl hosts this
# bridge rather than LibPARI.jl because the CI cost lands on the host, and
# `PARI_jll` (19 MB, ~13 deps) is far cheaper for Giac.jl to pull than
# `GIAC_jll` (73 MB, ~56 deps) would be for LibPARI.jl.
#
# CONTRACT — value-preserving and name-preserving; NOT representation-
# preserving.
#
#   * A PARI polynomial carries a variable *number* with a process-global
#     *priority*. `varhigher`/`varlower` change it for the whole process, so
#     `(w+x)^2` prints as `x^2+2*w*x+w^2` or `w^2+2*x*w+x^2` depending on the
#     ordering in force. Giac has its own ordering rules. The variable *name*
#     survives both crossings; the ordering does not.
#   * Compare round trips by value — `pari(to_giac(g)) == g`, where `==` on a
#     `Gen` is PARI's `gequal`. Never compare by `string`: that assertion is
#     red or flaky by construction.
#
# Two entry points, matching the convention LibPARI's own Symbolics bridge
# established:
#
#   outward (PARI → Giac)   `Giac.to_giac(g::LibPARI.Gen)`
#   inward  (Giac → PARI)   `LibPARI.pari(e::GiacExpr)`
#
# Adding a method to `LibPARI.pari` is not piracy: LibPARI owns `pari`, Giac
# owns `GiacExpr`. There is deliberately no second inward name.
#
# See docs/src/extensions/libpari.md for the full mapping table, the refusal
# list and the measured limitations.
# ---------------------------------------------------------------------------

module GiacLibPARIExt

using Giac
using Giac.GenTypes
using LibPARI

const PT = LibPARI.PariType
const P = LibPARI.PARI

# Tags this bridge translates, quoted in every refusal message so the caller
# learns the supported set from the error itself.
const OUTWARD_SUPPORTED =
    "T_INT, T_FRAC, T_REAL, T_COMPLEX, T_POL, T_VEC, T_COL, T_VECSMALL, " *
    "T_LIST and T_MAT"
const INWARD_SUPPORTED = "INT, ZINT, FRAC, DOUBLE, REAL, CPLX, IDNT, SYMB and VECT"

# ===========================================================================
# Reals
#
# Neither direction may go through a printed decimal chosen by a printer: a
# PARI `t_REAL` prints at the ambient `realprecision`, so injecting one into
# GP as text turns a 512-bit real into 128 bits with no diagnostic.
#
# PARI → Giac is structural on both legs. `BigFloat(::Gen)` widens the
# working precision to hold the mantissa exactly, and `LibPARI.pari` builds a
# `t_REAL` from a `BigFloat`'s mantissa and exponent.
#
# Giac → Julia is the one place the bridge has no structural route: the
# libgiac wrapper exposes `to_double` (a `Float64`, and therefore lossy) and
# nothing for an MPFR value, and reaching past it into an undeclared libgiac
# C symbol is exactly the class of call this project does not make. Giac's
# printer does, however, emit a REAL at that value's *own* precision rather
# than at a global setting — so the decimal is faithful, and only the bit
# width has to be recovered. `_giac_real_to_bigfloat` recovers it by search
# and *verifies* the result: the candidate is accepted only when re-encoding
# it reproduces Giac's own printed form character for character.
#
# That verification only closes for a REAL that reached Giac through Julia,
# whose stored rendering is MPFR's shortest round-tripping decimal. Giac
# prints a REAL it built itself — `evalf(x, d)` — in its own fixed-digit
# form, a different decimal for the same bits, and the verification leg
# normalises that away by going back out through `string(::BigFloat)`. For
# those the search finds nothing and the fallback keeps every digit Giac
# printed, which is all the text carries.
# ===========================================================================

# Significant decimal digits in Giac's rendering of a REAL.
function _significant_digits(s::AbstractString)
    mantissa = first(split(s, r"[eE]"))
    return count(isdigit, mantissa)
end

# Narrowest width that can hold `d` significant decimal digits.
_width_for_digits(d::Integer) = max(2, ceil(Int, d * log2(10)))

"""
Recover the `BigFloat` behind a Giac `REAL`.

A REAL that reached Giac through Julia carries MPFR's shortest
round-tripping decimal, and its width is recoverable exactly: MPFR renders a
`p`-bit value with `ceil(p * log10(2)) + 1` significant digits, which pins
`p` only to within a few bits, and the loop closes that gap by re-encoding
each candidate and keeping the width whose rendering matches.

A REAL that Giac built itself — `evalf(x, d)` — is printed in Giac's own
fixed-digit form instead, which is a *different decimal for the same value*.
The verification leg cannot see that width, because it goes back out through
`string(::BigFloat)`, which normalises to the shortest form. For those the
loop finds nothing, and the fallback holds every digit Giac printed.
"""
function _giac_real_to_bigfloat(g::GiacExpr)
    s = string(g)
    tryparse(BigFloat, s) === nothing &&
        throw(ArgumentError("pari: cannot read the Giac REAL `$s` as a BigFloat"))
    d = _significant_digits(s)
    lo = max(2, floor(Int, (d - 2) / log10(2)) - 8)
    hi = ceil(Int, (d - 1) / log10(2)) + 8
    for p = lo:hi
        b = setprecision(() -> parse(BigFloat, s), BigFloat, p)
        string(convert(GiacExpr, b)) == s && return b
    end
    # Not a failure to read the value. Giac re-reads this decimal into the
    # same REAL, so it is faithful; what is unavailable is the width that
    # produced it, since Giac's fixed-digit rendering and MPFR's shortest one
    # disagree for the same bits. Take the narrowest width that holds every
    # digit Giac printed — never fewer, so nothing it showed us is dropped.
    return setprecision(() -> parse(BigFloat, s), BigFloat, _width_for_digits(d))
end

# ===========================================================================
# PARI → Giac
# ===========================================================================

# The name of a polynomial's main variable, as PARI reports it. `gpolvar`
# returns the free symbol itself, whose text is the name; note the keyword —
# it takes `x1 = g`, not a positional argument.
_mainvar_name(g::LibPARI.Gen) = string(P.gpolvar(; x1 = g))

_refuse_outward(t) = throw(
    ArgumentError(
        "to_giac: no Giac counterpart for the PARI tag $t; the bridge covers " *
        OUTWARD_SUPPORTED,
    ),
)

"""
    to_giac(g::LibPARI.Gen) -> GiacExpr

Convert a PARI/GP value to a Giac expression.

The conversion is value-preserving and name-preserving, but not
representation-preserving: PARI's variable priority — a process-global
ordering — does not cross, and Giac reorders by its own rules. Compare round
trips with `==`, never with `string`.

Supported tags: `T_INT`, `T_FRAC`, `T_REAL`, `T_COMPLEX`, `T_POL`, `T_VEC`,
`T_COL`, `T_VECSMALL`, `T_LIST` and `T_MAT`. Any other tag raises an
`ArgumentError` naming it. `T_COL`, `T_VECSMALL` and `T_LIST` widen to a Giac
`VECT` and therefore return as a `T_VEC`.

# Examples

```julia
using Giac, LibPARI

to_giac(pari(3 // 4))                # 3/4
to_giac(gp_eval("(w+x)^2"))          # a Giac SYMB in w and x
pari(to_giac(gp_eval("x^2+1")))      # back again, equal by `==`
```

See also [`LibPARI.pari`](@ref) for the inward direction.
"""
function Giac.to_giac(g::LibPARI.Gen)::GiacExpr
    t = LibPARI.gentype(g)

    if t === PT.T_INT
        return convert(GiacExpr, BigInt(g))
    elseif t === PT.T_FRAC
        return convert(GiacExpr, Rational{BigInt}(g))
    elseif t === PT.T_REAL
        # `BigFloat(::Gen)` widens as needed, so this leg never rounds.
        return convert(GiacExpr, BigFloat(g))
    elseif t === PT.T_COMPLEX
        return Giac.to_giac(real(g)) + Giac.to_giac(imag(g)) * giac_eval("i")
    elseif t === PT.T_POL
        return _pol_to_giac(g)
    elseif t === PT.T_VEC || t === PT.T_COL || t === PT.T_VECSMALL || t === PT.T_LIST
        return _giac_vect([Giac.to_giac(x) for x in g])
    elseif t === PT.T_MAT
        nrows, ncols = size(g)
        return _giac_vect([
            _giac_vect([Giac.to_giac(g[i, j]) for j = 1:ncols]) for i = 1:nrows
        ])
    end

    return _refuse_outward(t)
end

# Horner over the main variable; each coefficient converts recursively, so a
# multivariate polynomial nests correctly. A `t_POL` of degree 0 collapses to
# its constant, which is what PARI's own `==` compares it to.
function _pol_to_giac(g::LibPARI.Gen)::GiacExpr
    iszero(g) && return convert(GiacExpr, 0)
    v = giac_eval(_mainvar_name(g))
    d = LibPARI.degree(g)
    acc = Giac.to_giac(LibPARI.coeff(g, d))
    for k = (d-1):-1:0
        acc = acc * v + Giac.to_giac(LibPARI.coeff(g, k))
    end
    return acc
end

# A Giac VECT from Julia-side elements, built through Giac's own vector
# constructor rather than by printing the elements into a bracket list.
#
# `makevector` is not a faithful wrapper at length one: handed a single
# vector it returns that vector instead of a vector containing it, which
# would silently turn a one-row PARI `t_MAT` into a flat `t_VEC` on the way
# back. Length one therefore goes through `mid`, which does wrap.
function _giac_vect(xs::Vector{GiacExpr})::GiacExpr
    isempty(xs) && return giac_eval("[]")
    length(xs) == 1 &&
        return Giac.Commands.mid(Giac.Commands.makevector(xs[1], xs[1]), 0, 1)
    return Giac.Commands.makevector(xs...)
end

# ===========================================================================
# Giac → PARI
# ===========================================================================

# PARI's imaginary unit, fetched by name through GP. A *name* through text is
# safe — it is the value round trip that loses precision.
_pari_i() = LibPARI.gp_eval("I")

_refuse_inward(t, why = "") = throw(
    ArgumentError(
        "pari: no PARI counterpart for the Giac tag $t" *
        (isempty(why) ? "" : " ($why)") *
        "; the bridge covers " *
        INWARD_SUPPORTED,
    ),
)

"""
    LibPARI.pari(e::Giac.GiacExpr) -> LibPARI.Gen

Convert a Giac expression to a PARI/GP value.

This is a method on LibPARI's own single inward entry point, not a second
name: `pari` is LibPARI's, `GiacExpr` is Giac's, so the method is well-owned
by neither package alone and lives in this bridge.

Supported tags: `INT`, `ZINT`, `FRAC`, `DOUBLE`, `REAL`, `CPLX`, `IDNT`,
`SYMB` (when the expression is a polynomial in its free identifiers) and
`VECT`. Any other tag — `MOD`, `STRNG`, `POLY`, `FUNC`, … — raises an
`ArgumentError` naming it.

# Examples

```julia
using Giac, LibPARI

pari(giac_eval("3/4"))               # 3/4, a t_FRAC
pari(giac_eval("x^2+1"))             # x^2 + 1, a t_POL
to_giac(pari(giac_eval("[1,2,3]")))  # round trip through a t_VEC
```

See also [`Giac.to_giac`](@ref) for the outward direction.
"""
function LibPARI.pari(e::GiacExpr)::LibPARI.Gen
    t = Giac.giac_type(e)

    if t == INT
        return LibPARI.pari(to_julia(e))
    elseif t == ZINT
        return LibPARI.pari(BigInt(to_julia(e)))
    elseif t == DOUBLE
        return LibPARI.pari(Float64(to_julia(e)))
    elseif t == REAL
        return LibPARI.pari(_giac_real_to_bigfloat(e))
    elseif t == FRAC
        # `numer`/`denom` recurse, which also covers Giac's habit of storing a
        # complex number with rational parts as a FRAC — `(3+2*i)/4`, whose
        # `real_part` is the whole fraction rather than `3/4`.
        return LibPARI.pari(Giac.numer(e)) / LibPARI.pari(Giac.denom(e))
    elseif t == CPLX
        return LibPARI.pari(Giac.real_part(e)) + LibPARI.pari(Giac.imag_part(e)) * _pari_i()
    elseif t == IDNT
        # `pi`, `e` and friends are IDNTs too, and a PARI variable named `pi`
        # is not Giac's π. Refuse rather than invent one.
        Giac.is_constant(e) && _refuse_inward(
            t,
            "`$e` is a Giac constant, not a free variable; PARI has no " *
            "same-named counterpart and a variable of that name would not " *
            "mean the same thing",
        )
        return LibPARI.gp_eval(string(e))
    elseif t == SYMB
        return _symb_to_pari(e)
    elseif t == VECT
        return _vect_to_pari(e)
    end

    return _refuse_inward(t)
end

# --- polynomials -----------------------------------------------------------

# A Giac SYMB reaches PARI only when it is a polynomial in its free
# identifiers. `lvar` reports the *generalised* variables of an expression:
# `sqrt(2)`, `sin(x)` and `exp(x)` each come back as a variable of their own
# rather than as an identifier, which is precisely the test for "polynomial
# in identifiers". `1/x` and `x/(x+1)` pass that test but are rational
# functions, so the denominator is checked separately.
function _symb_to_pari(e::GiacExpr)::LibPARI.Gen
    vars = _elements(Giac.Commands.lvar(e))

    for v in vars
        Giac.giac_type(v) == IDNT || _refuse_inward(
            SYMB,
            "`$e` is not a polynomial in identifiers — Giac reports `$v` as one " *
            "of its variables",
        )
        Giac.is_constant(v) && _refuse_inward(
            SYMB,
            "`$e` involves the Giac constant `$v`, which has no PARI counterpart",
        )
    end

    # `Giac.denom` is restricted to fractions and integers; the Giac command
    # of the same name answers for any expression, and reports `x+1` for
    # `x/(x+1)` and `1` for `x^2+1`.
    den = Giac.Commands.denom(e)
    isempty(_elements(Giac.Commands.lvar(den))) || _refuse_inward(
        SYMB,
        "`$e` is a rational function with denominator `$den`, not a polynomial; " *
        "PARI would represent it as a t_RFRAC, which this bridge does not cover",
    )

    isempty(vars) && return LibPARI.pari(to_julia(e))

    v = first(vars)
    coeffs = _elements(Giac.Commands.symb2poly(e, v))
    isempty(coeffs) && return LibPARI.pari(0)

    # `symb2poly` returns coefficients in descending degree.
    pv = LibPARI.gp_eval(string(v))
    acc = LibPARI.pari(first(coeffs))
    for c in coeffs[2:end]
        acc = acc * pv + LibPARI.pari(c)
    end
    return acc
end

# --- containers ------------------------------------------------------------

_elements(v::GiacExpr)::Vector{GiacExpr} =
    Giac.giac_type(v) == VECT ? GiacExpr[v[i] for i = 1:length(v)] : GiacExpr[]

# Build a `t_VEC` from its elements.
#
# `Vec(x)` is *not* a one-element wrapper: on a `t_POL` it returns the
# coefficient vector and on a container it flattens, so `Vec` cannot start
# this fold. `concat` is the right primitive — it splices vectors and
# matrices but treats a `t_POL` as a scalar — and `vecextract` supplies the
# one-element case that `concat` alone cannot express.
#
# Callers must therefore pass scalars or polynomials only; `_vect_to_pari`
# routes a nested Giac vector to `t_MAT` and refuses every other nesting.
function _pari_vec(xs::Vector{LibPARI.Gen})::LibPARI.Gen
    isempty(xs) && return LibPARI.gp_eval("[]")
    length(xs) == 1 &&
        return P.extract0(P.gconcat(first(xs); x2 = first(xs)), LibPARI.pari(1); x3 = nothing)
    return foldl(
        (a, b) -> P.gconcat(a; x2 = b),
        xs[3:end];
        init = P.gconcat(xs[1]; x2 = xs[2]),
    )
end

function _vect_to_pari(e::GiacExpr)::LibPARI.Gen
    rows = _elements(e)
    isempty(rows) && return LibPARI.gp_eval("[]")

    if all(r -> Giac.giac_type(r) == VECT, rows)
        widths = [length(r) for r in rows]
        allequal(widths) || throw(
            ArgumentError(
                "pari: the Giac VECT `$e` nests vectors of differing lengths " *
                "$(widths); PARI has no ragged container, and this bridge maps " *
                "only a rectangular nesting onto a t_MAT",
            ),
        )
        first(widths) == 0 && return LibPARI.gp_eval("[]")

        ncols = first(widths)
        cols = LibPARI.Gen[]
        for j = 1:ncols
            col = P.gtocol0(
                _pari_vec(LibPARI.Gen[LibPARI.pari(r[j]) for r in rows]);
                x2 = 0,
            )
            push!(cols, P.gtomat(; x1 = col))
        end
        return foldl((a, b) -> P.gconcat(a; x2 = b), cols[2:end]; init = first(cols))
    end

    any(r -> Giac.giac_type(r) == VECT, rows) && throw(
        ArgumentError(
            "pari: the Giac VECT `$e` mixes vector and scalar elements; PARI " *
            "has no counterpart for that shape",
        ),
    )

    return _pari_vec(LibPARI.Gen[LibPARI.pari(r) for r in rows])
end

end # module GiacLibPARIExt
