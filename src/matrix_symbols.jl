# Symbolic matrices: a matrix as a single symbol, with products that do not commute.
#
# An expression is kept in a canonical form, a sum of terms, each a scalar coefficient (a GiacExpr)
# times a word: a product of factors, each a matrix symbol transposed or not, to an integer power
# (negative for an inverse). The identities of matrix algebra hold by construction of that form:
# (AB)ᵀ = BᵀAᵀ, (AB)⁻¹ = B⁻¹A⁻¹, AA⁻¹ = I, Pᵀ = P for a symmetric P, Wᵀ = -W for a skew W,
# Q⁻¹ = Qᵀ for an orthogonal Q, and a 1×1 term equals its transpose.
#
# Ported from Kahli Burke's `ergonomics` branch (src/matrix_symbols.jl). Not ported: the facts
# recorded for the rules engine (`Giac.Rules`: det P > 0, (det Q)² = 1), and the textbook LaTeX
# of the presentation layer; the LaTeX here is a simple one, coefficients through GIAC's `latex`.

# A GIAC identifier for a name, quoted so that a value GIAC holds for it is not substituted
# (the ergonomics branch's `giac_identifier`, from its unported macros.jl)
_matsym_identifier(name::AbstractString) = giac_eval("'" * name * "'")

"A dimension: a number, or a name for one (`n`)."
const Dim = Union{Int, Symbol}

const _MATRIX_SYMBOL_PROPERTIES = (:symmetric, :skew, :orthogonal, :posdef, :negdef, :invertible, :diagonal)

"""
    MatrixSymbol

A matrix as a single symbol, with a size (numbers or names) and properties. Made by
[`@matsym`](@ref); used through the [`MatExpr`](@ref) it stands for.
"""
struct MatrixSymbol
    name::Symbol
    rows::Dim
    cols::Dim
    properties::Vector{Symbol}
end
Base.:(==)(a::MatrixSymbol, b::MatrixSymbol) = a.name === b.name
Base.hash(a::MatrixSymbol, h::UInt) = hash(a.name, hash(:MatrixSymbol, h))

_has(s::MatrixSymbol, p) = p in s.properties
_symmetric(s::MatrixSymbol) = any(p -> _has(s, p), (:symmetric, :posdef, :negdef, :diagonal))

"""
    Factor

A factor of a product: `base` (a [`MatrixSymbol`](@ref), or a sum kept whole under an inverse)
transposed or not, to an integer power.
"""
struct Factor
    base::Any
    transposed::Bool
    power::Int
end

const Word = Vector{Factor}

"""
    MatExpr

A matrix expression: a sum of terms, each a scalar coefficient (a `GiacExpr`) times a word, a
product of [`Factor`](@ref)s in order. Kept canonical, so equal expressions are written the same.
Built from symbols declared with [`@matsym`](@ref) by `+`, `-`, `*`, scalars, `transpose` (`'`),
`inv`, integer powers, `I`, `tr` and `det`.
"""
struct MatExpr
    rows::Dim
    cols::Dim
    terms::Vector{Pair{Word, GiacExpr}}
end

"""
    Kron

The Kronecker product `A ⊗ B` as one factor of a product, of two single products `A` and `B`
(see `kron`). It is kept untransposed and to the first power: (A⊗B)ᵀ = Aᵀ⊗Bᵀ, (A⊗B)ᵏ = Aᵏ⊗Bᵏ,
and neighbours multiply as (A⊗B)(C⊗D) = AC⊗BD.
"""
struct Kron
    A::MatExpr
    B::MatExpr
end

"""
    ConstMatrix

A constant matrix of a given structure, one factor of a product:
- `:commutation`, `K(a, b)`: the `ab × ab` permutation with `vec(Xᵀ) = K vec X` for `X` `a × b`;
- `:duplication`, `D(n)`: the `n² × n(n+1)/2` matrix with `vec P = D vech P` for a symmetric `P`;
- `:duplication_plus`, `D⁺(n)`: its left inverse `(DᵀD)⁻¹Dᵀ`, with `vech P = D⁺ vec P`.
"""
struct ConstMatrix
    kind::Symbol
    a::Dim
    b::Dim
end

# Sizes multiply under ⊗, and a duplication matrix has n(n+1)/2 columns: a size is a number, a
# name, or an integer expression in names (`m*n`, `(n+1)/2*n`), its factors kept sorted
function _dim_factors(d::Symbol)
    s, out, depth, start = string(d), String[], 0, 1
    for (i, c) in pairs(s)
        c == '(' ? (depth += 1) : c == ')' ? (depth -= 1) : nothing
        if c == '*' && depth == 0
            push!(out, s[start:prevind(s, i)])
            start = nextind(s, i)
        end
    end
    push!(out, s[start:end])
    return out
end
_dim_factors(d::Int) = d == 1 ? String[] : [string(d)]
_vech_dim(n::Int) = n * (n + 1) ÷ 2
_vech_dim(n::Symbol) = _dim_mul(n, Symbol("(" * string(n) * "+1)/2"))
function _dim_mul(a::Dim, b::Dim)
    a isa Int && b isa Int && return a * b
    fs = sort!(vcat(_dim_factors(a), _dim_factors(b)))
    ints = prod((parse(Int, f) for f in fs if occursin(r"^\d+$", f)); init = 1)
    names = [f for f in fs if !occursin(r"^\d+$", f)]
    isempty(names) && return ints
    return Symbol(join(vcat(ints == 1 ? String[] : [string(ints)], names), "*"))
end

# ---------------------------------------------------------------------------------------------
# Keys: a word written as text, to order terms and compare words
# ---------------------------------------------------------------------------------------------

_base_key(b::MatrixSymbol) = string(b.name)
_base_key(b::Kron) = "kron(" * _plain(b.A) * "," * _plain(b.B) * ")"
_base_key(b::ConstMatrix) = string(b.kind, "(", b.a, ",", b.b, ")")
_base_key(b::MatExpr) = "(" * _plain(b) * ")"
_factor_key(f::Factor) = _base_key(f.base) * (f.transposed ? "'" : "") * (f.power == 1 ? "" : "^" * string(f.power))
_word_key(w::Word) = join(map(_factor_key, w), "*")

# the order in which equal words are chosen: shorter, then with fewer transposes, then by text
_word_rank(w::Word) = (length(w), count(f -> f.transposed, w), _word_key(w))

_dim_string(d::Dim) = string(d)
_same_dim(a::Dim, b::Dim) = a == b
_square(b::MatrixSymbol) = b.rows == b.cols
_square(b::MatExpr) = b.rows == b.cols
_rows(f::Factor) = f.transposed ? _cols(f.base) : _rows(f.base)
_cols(f::Factor) = f.transposed ? _rows(f.base) : _cols(f.base)
_rows(b::MatrixSymbol) = b.rows; _cols(b::MatrixSymbol) = b.cols
_rows(b::MatExpr) = b.rows; _cols(b::MatExpr) = b.cols
_rows(b::Kron) = _dim_mul(b.A.rows, b.B.rows); _cols(b::Kron) = _dim_mul(b.A.cols, b.B.cols)
_rows(b::ConstMatrix) = b.kind === :commutation ? _dim_mul(b.a, b.b) : b.kind === :duplication ? _dim_mul(b.a, b.a) : _vech_dim(b.a)
_cols(b::ConstMatrix) = b.kind === :commutation ? _dim_mul(b.a, b.b) : b.kind === :duplication ? _vech_dim(b.a) : _dim_mul(b.a, b.a)

# ---------------------------------------------------------------------------------------------
# Canonical words
# ---------------------------------------------------------------------------------------------

# A factor in canonical form, and the sign it takes on: a symmetric matrix is its transpose, a
# skew one minus its transpose, an orthogonal one's transpose is its inverse, and a transposed
# sum under an inverse has the transpose taken inside.
function _canonical(f::Factor)
    b = f.base
    if b isa ConstMatrix && b.kind === :commutation
        (b.a == 1 || b.b == 1) && return (1, Factor(b, false, 0))           # the identity
        flip = f.transposed ⊻ (f.power < 0)
        p = abs(f.power)
        b.a == b.b && (p %= 2)
        (p > 1) && throw(DimensionMismatch("a power of the non-square-blocked $(_base_key(b))"))
        return (1, Factor(flip ? ConstMatrix(:commutation, b.b, b.a) : b, false, p))
    end
    b isa ConstMatrix && return (1, f)
    if b isa Kron
        (f.transposed || f.power != 1) || return (1, f)
        A, B = f.transposed ? (transpose(b.A), transpose(b.B)) : (b.A, b.B)
        k = f.power
        A, B = k == 1 ? (A, B) : k < 0 ? (inv(A)^(-k), inv(B)^(-k)) : (A^k, B^k)
        return _kron_factor(A, B)
    end
    if b isa MatExpr
        return f.transposed ? (1, Factor(transpose(b), false, f.power)) : (1, f)
    end
    f.transposed || return (1, f)
    _symmetric(b) && return (1, Factor(b, false, f.power))
    _has(b, :skew) && return (isodd(f.power) ? -1 : 1, Factor(b, false, f.power))
    _has(b, :orthogonal) && return (1, Factor(b, false, -f.power))
    return (1, f)
end

_same_base(a::Factor, b::Factor) = _base_key(a.base) == _base_key(b.base)

"""
A word in canonical form, and its sign: each factor canonical, and adjacent factors of the same
base (and transposition) merged, powers adding, a power 0 dropping out, which may bring others
together.
"""
function _normalize(w::Word)
    sign = 1
    out = Factor[]
    for (i, f) in pairs(w)
        s, f = _canonical(f)
        sign *= s
        f.power == 0 && continue
        r = isempty(out) ? nothing : _const_rule(out[end], f)
        if r !== nothing
            # a rule for a constant factor: what replaces the pair, normalized with the rest
            pop!(out)
            s2, rest = _normalize(vcat(out, r, w[(i + 1):end]))
            return sign * s2, rest
        elseif !isempty(out) && out[end].base isa Kron && f.base isa Kron && _kron_fits(out[end].base, f.base)
            # (A⊗B)(C⊗D) = AC⊗BD
            a, b = pop!(out).base, f.base
            s, k = _kron_factor(a.A * b.A, a.B * b.B)
            sign *= s
            k === nothing || push!(out, k)
        elseif !isempty(out) && _same_base(out[end], f) && out[end].transposed == f.transposed
            p = out[end].power + f.power
            pop!(out)
            p == 0 || push!(out, Factor(f.base, f.transposed, p))
        else
            push!(out, f)
        end
    end
    return sign, out
end

# A ⊗ B of single products as a factor, with the sign that comes out of them; no factor (nothing)
# for I ⊗ I, which is the identity
function _kron_factor(A::MatExpr, B::MatExpr)
    (length(A.terms) == 1 && length(B.terms) == 1) || throw(ArgumentError("a Kronecker factor holds single products"))
    (wa, ca), (wb, cb) = only(A.terms), only(B.terms)
    c = Commands.normal(ca * cb)
    sign = string(c) == "1" ? 1 : string(c) == "-1" ? -1 :
           throw(ArgumentError("a Kronecker factor's coefficient is ±1, got $c"))
    isempty(wa) && isempty(wb) && return (sign, nothing)
    unit(w, M) = MatExpr(M.rows, M.cols, [w => one(GiacExpr)])
    return (sign, Factor(Kron(unit(wa, A), unit(wb, B)), false, 1))
end

_kron_fits(a::Kron, b::Kron) = _same_dim(a.A.cols, b.A.rows) && _same_dim(a.B.cols, b.B.rows)

_is_const(f::Factor, kind) = f.base isa ConstMatrix && f.base.kind === kind && f.power == 1

# The factors that replace a pair `f g` with a commutation or duplication matrix in it, or nothing:
# K(a,b)K(b,a) = I, D⁺D = I, K(n,n)D = D, D⁺K(n,n) = D⁺, DᵀK(n,n) = Dᵀ, and K moves to the right
# of a Kronecker product: K(p,m)(A⊗B) = (B⊗A)K(q,n) for A m×n, B p×q.
function _const_rule(f::Factor, g::Factor)
    if _is_const(f, :commutation)
        k = f.base
        if _is_const(g, :commutation) && g.base.a == k.b && g.base.b == k.a
            return Factor[]
        elseif _is_const(g, :duplication) && !g.transposed && k.a == k.b == g.base.a
            return Factor[g]
        elseif g.base isa Kron && g.power == 1 && !g.transposed &&
               _same_dim(g.base.B.rows, k.a) && _same_dim(g.base.A.rows, k.b)
            A, B = g.base.A, g.base.B
            return Factor[Factor(Kron(B, A), false, 1), Factor(ConstMatrix(:commutation, B.cols, A.cols), false, 1)]
        end
    elseif _is_const(f, :duplication_plus) && !f.transposed
        _is_const(g, :duplication) && !g.transposed && g.base.a == f.base.a && return Factor[]
        _is_const(g, :commutation) && g.base.a == g.base.b == f.base.a && return Factor[f]
    elseif _is_const(f, :duplication) && f.transposed
        _is_const(g, :commutation) && g.base.a == g.base.b == f.base.a && return Factor[f]
    end
    return nothing
end

# the transpose of a word: reversed, each factor transposed
function _transpose_word(w::Word)
    sign, out = _normalize(Factor[Factor(f.base, !f.transposed, f.power) for f in Iterators.reverse(w)])
    return sign, out
end

# the inverse of a word of square factors: reversed, each power negated
_inverse_word(w::Word) = _normalize(Factor[Factor(f.base, f.transposed, -f.power) for f in Iterators.reverse(w)])

# ---------------------------------------------------------------------------------------------
# Building expressions
# ---------------------------------------------------------------------------------------------

_coefficient(c) = c isa GiacExpr ? c : convert(GiacExpr, c)
_tidy(c::GiacExpr) = Commands.normal(c)
_iszero_coefficient(c::GiacExpr) = string(c) == "0"

"""
An expression of size `rows × cols` from terms `word => coefficient` (words not yet canonical):
words normalized, like terms combined, zero terms dropped. A 1×1 term equals its transpose, so
it is written as whichever of the two words comes first.
"""
function _matexpr(rows::Dim, cols::Dim, terms)
    acc = Dict{String, Tuple{Word, GiacExpr}}()
    for (w, c) in terms
        sign, w = _normalize(w)
        if rows == 1 && cols == 1
            tsign, tw = _transpose_word(w)
            _word_rank(tw) < _word_rank(w) && ((sign, w) = (sign * tsign, tw))
        end
        k = _word_key(w)
        c = sign == 1 ? _coefficient(c) : -_coefficient(c)
        acc[k] = haskey(acc, k) ? (w, acc[k][2] + c) : (w, c)
    end
    out = Pair{Word, GiacExpr}[]
    for k in sort!(collect(keys(acc)); by = k -> (length(acc[k][1]), k))
        w, c = acc[k]
        c = _tidy(c)
        _iszero_coefficient(c) || push!(out, w => c)
    end
    cancelled = _cancel_inverse(rows, cols, out)
    return cancelled === nothing ? MatExpr(rows, cols, out) : cancelled
end

# The inverse of a sum cancels against the sum: terms `u M⁻¹ vᵢ` whose `vᵢ` add up to λM are λu
# (and `uᵢ M⁻¹ v` whose `uᵢ` add up to λM are λv). The expression with that done, or `nothing`.
function _cancel_inverse(rows, cols, terms)
    for (w, _) in terms, (k, f) in enumerate(w)
        (f.base isa MatExpr && f.power == -1 && !f.transposed) || continue
        M = f.base
        for side in (:left, :right)
            fixed = side === :left ? w[1:k] : w[k:end]
            key = _word_key(fixed)
            group, rest = Pair{Word, GiacExpr}[], Pair{Word, GiacExpr}[]
            for (ww, c) in terms
                n = length(fixed)
                part = length(ww) >= n ? (side === :left ? ww[1:n] : ww[(end - n + 1):end]) : Factor[]
                if length(ww) >= n && _word_key(part) == key
                    push!(group, (side === :left ? ww[(n + 1):end] : ww[1:(end - n)]) => c)
                else
                    push!(rest, ww => c)
                end
            end
            size_ok = side === :left ? cols == M.cols : rows == M.rows
            size_ok || continue
            λ = _multiple_of(_matexpr(M.rows, M.cols, group), M)
            λ === nothing && continue
            outer = side === :left ? w[1:(k - 1)] : w[(k + 1):end]
            return _matexpr(rows, cols, vcat(rest, [outer => λ]))
        end
    end
    return nothing
end

# λ with R = λM, or `nothing`
function _multiple_of(R::MatExpr, M::MatExpr)
    (isempty(R.terms) || isempty(M.terms) || length(R.terms) != length(M.terms)) && return nothing
    w1, c1 = first(M.terms)
    i = findfirst(t -> _word_key(first(t)) == _word_key(w1), R.terms)
    i === nothing && return nothing
    λ = _tidy(last(R.terms[i]) / c1)
    return iszero(R - λ * M) ? λ : nothing
end

"The expression standing for a matrix symbol."
MatExpr(s::MatrixSymbol) = MatExpr(s.rows, s.cols, [Factor[Factor(s, false, 1)] => one(GiacExpr)])

"""
    identity_matrix(n)

The `n × n` identity, as a matrix expression (`n` a number or a name). `A + I` also works.
"""
identity_matrix(n::Dim) = MatExpr(n, n, [Factor[] => one(GiacExpr)])
zero_matrix(m::Dim, n::Dim) = MatExpr(m, n, Pair{Word, GiacExpr}[])

Base.zero(M::MatExpr) = zero_matrix(M.rows, M.cols)
Base.one(M::MatExpr) = (_square_check(M); identity_matrix(M.rows))
Base.size(M::MatExpr) = (M.rows, M.cols)
Base.size(M::MatExpr, d::Integer) = size(M)[d]
Base.iszero(M::MatExpr) = isempty(M.terms)

_square_check(M::MatExpr) = M.rows == M.cols ||
    throw(DimensionMismatch("$(_plain(M)) is $(M.rows)×$(M.cols), not square"))

function _check_same_size(A::MatExpr, B::MatExpr, op)
    (A.rows == B.rows && A.cols == B.cols) ||
        throw(DimensionMismatch("$op of a $(A.rows)×$(A.cols) and a $(B.rows)×$(B.cols) matrix"))
end

Base.:+(A::MatExpr, B::MatExpr) = (_check_same_size(A, B, "sum"); _matexpr(A.rows, A.cols, vcat(A.terms, B.terms)))
Base.:-(A::MatExpr) = MatExpr(A.rows, A.cols, [w => -c for (w, c) in A.terms])
Base.:-(A::MatExpr, B::MatExpr) = A + (-B)

const _Scalar = Union{Number, GiacExpr}
Base.:*(c::_Scalar, A::MatExpr) = _matexpr(A.rows, A.cols, [w => _coefficient(c) * k for (w, k) in A.terms])
Base.:*(A::MatExpr, c::_Scalar) = c * A
Base.:/(A::MatExpr, c::_Scalar) = inv(_coefficient(c)) * A

function Base.:*(A::MatExpr, B::MatExpr)
    if !_same_dim(A.cols, B.rows)
        # a 1×1 factor that does not fit as a matrix is a scalar: (xᵀx) b
        A.rows == 1 && A.cols == 1 && return tr(A) * B
        B.rows == 1 && B.cols == 1 && return A * tr(B)
        throw(DimensionMismatch("product of a $(A.rows)×$(A.cols) and a $(B.rows)×$(B.cols) matrix"))
    end
    return _matexpr(A.rows, B.cols, [vcat(wa, wb) => ca * cb for (wa, ca) in A.terms for (wb, cb) in B.terms])
end

# the identity: `A + I`, `λ * I`
Base.:+(A::MatExpr, J::UniformScaling) = (_square_check(A); A + _coefficient(J.λ) * identity_matrix(A.rows))
Base.:+(J::UniformScaling, A::MatExpr) = A + J
Base.:-(A::MatExpr, J::UniformScaling) = A + (-J)
Base.:-(J::UniformScaling, A::MatExpr) = (-A) + J
Base.:*(A::MatExpr, J::UniformScaling) = _coefficient(J.λ) * A
Base.:*(J::UniformScaling, A::MatExpr) = _coefficient(J.λ) * A

# a 1×1 expression with a scalar: the scalar is that multiple of the 1×1 identity
function Base.:+(A::MatExpr, c::_Scalar)
    (A.rows == 1 && A.cols == 1) || throw(DimensionMismatch("adding a scalar to a $(A.rows)×$(A.cols) matrix; use `+ c * I`"))
    return A + _coefficient(c) * identity_matrix(1)
end
Base.:+(c::_Scalar, A::MatExpr) = A + c
Base.:-(A::MatExpr, c::_Scalar) = A + (-_coefficient(c))
Base.:-(c::_Scalar, A::MatExpr) = (-A) + c

function Base.transpose(A::MatExpr)
    terms = Pair{Word, GiacExpr}[]
    for (w, c) in A.terms
        sign, tw = _transpose_word(w)
        push!(terms, tw => (sign == 1 ? c : -c))
    end
    return _matexpr(A.cols, A.rows, terms)
end
# real matrices: the adjoint (`A'`) is the transpose
Base.adjoint(A::MatExpr) = transpose(A)

"""
    inv(A::MatExpr)

The inverse. A single product of square factors inverts factor by factor, `(cAB)⁻¹ = B⁻¹A⁻¹/c`;
a sum is kept whole, `(A + B)⁻¹`.
"""
function Base.inv(A::MatExpr)
    _square_check(A)
    isempty(A.terms) && throw(SingularException(0))
    if length(A.terms) == 1
        w, c = only(A.terms)
        if all(f -> _rows(f) == _cols(f), w)
            sign, iw = _inverse_word(w)
            return _matexpr(A.rows, A.cols, [iw => (sign == 1 ? inv(c) : -inv(c))])
        end
    end
    return _matexpr(A.rows, A.cols, [Factor[Factor(A, false, -1)] => one(GiacExpr)])
end

function Base.:^(A::MatExpr, n::Integer)
    _square_check(A)
    n < 0 && return inv(A)^(-n)
    R = identity_matrix(A.rows)
    for _ in 1:n
        R = R * A
    end
    return R
end
Base.literal_pow(::typeof(^), A::MatExpr, ::Val{n}) where {n} = A^n

Base.:(==)(A::MatExpr, B::MatExpr) = size(A) == size(B) && iszero(A - B)
Base.isequal(A::MatExpr, B::MatExpr) = size(A) == size(B) && _plain(A) == _plain(B)
Base.hash(A::MatExpr, h::UInt) = hash(_plain(A), hash(size(A), h))

# ---------------------------------------------------------------------------------------------
# Writing expressions: plain text and LaTeX
# ---------------------------------------------------------------------------------------------

# Plain text for an expression. With `readable`, traces and determinants in coefficients are written
# as such; without, as Giac's names for them, which is the form used as a key.
const _CONST_PLAIN = Dict(:commutation => "K", :duplication => "D", :duplication_plus => "Dplus")
function _const_plain(b::ConstMatrix)
    args = b.kind === :commutation ? "$(b.a), $(b.b)" : string(b.a)
    return _CONST_PLAIN[b.kind] * "(" * args * ")"
end
function _const_latex(b::ConstMatrix)
    b.kind === :commutation && return "K_{" * _dim_latex(b.a) * "," * _dim_latex(b.b) * "}"
    return "D_{" * _dim_latex(b.a) * "}" * (b.kind === :duplication_plus ? "^{+}" : "")
end

function _plain_factor(f::Factor, readable::Bool = false)
    f.base isa ConstMatrix && return _const_plain(f.base) * (f.transposed ? "'" : "")
    f.base isa Kron && return "kron(" * _plain(f.base.A, readable) * ", " * _plain(f.base.B, readable) * ")"
    b = f.base isa MatrixSymbol ? string(f.base.name) : "(" * _plain(f.base, readable) * ")"
    orthogonal = f.base isa MatrixSymbol && _has(f.base, :orthogonal)
    if orthogonal && f.power < 0
        return b * "'" * (f.power == -1 ? "" : "^" * string(-f.power))
    end
    t = f.transposed ? "'" : ""
    f.power == 1 && return b * t
    f.power == -1 && return "inv(" * b * t * ")"
    return (t == "" ? b : "(" * b * t * ")") * "^" * string(f.power)
end

function _plain(A::MatExpr, readable::Bool = false)
    isempty(A.terms) && return "0"
    parts = String[]
    for (w, c) in A.terms
        word = isempty(w) ? "I" : join((_plain_factor(f, readable) for f in w), "*")
        cs = readable ? _atom_plain(string(c)) : string(c)
        push!(parts, cs == "1" ? word : cs == "-1" ? "-" * word :
                     (occursin(r"[+-]", cs[nextind(cs, 1):end]) ? "(" * cs * ")" : cs) * "*" * word)
    end
    return replace(join(parts, " + "), "+ -" => "- ")
end

Base.show(io::IO, A::MatExpr) = print(io, _plain(A, true))
Base.show(io::IO, ::MIME"text/plain", A::MatExpr) = print(io, "MatExpr (", A.rows, "×", A.cols, "): ", _plain(A, true))

# LaTeX names of the symbols made from others (`dX`, `vec X`, `vech P`), by name; any other name
# is written as it is (the ergonomics branch's `_record_tex_name!`, of its presentation layer)
const _MATSYM_TEX = Dict{String, String}()
const _MATSYM_TEX_LOCK = ReentrantLock()
_record_matsym_tex!(name::AbstractString, tex::AbstractString) = lock(() -> (_MATSYM_TEX[name] = tex), _MATSYM_TEX_LOCK)
_matsym_tex(name::AbstractString) = lock(() -> get(_MATSYM_TEX, name, name), _MATSYM_TEX_LOCK)

# A scalar in LaTeX, by GIAC's `latex` (which returns a quoted string), with the traces and
# determinants of matrices written as such
function _scalar_latex(c::GiacExpr)
    s = string(invoke_cmd(:latex, c))
    s = length(s) >= 2 && startswith(s, '"') && endswith(s, '"') ? s[2:(end - 1)] : s
    return _atom_tex(s)
end

_symbol_latex(s::MatrixSymbol) = _matsym_tex(string(s.name))
_dim_latex(d::Dim) = d isa Int ? string(d) : _scalar_latex(_matsym_identifier(string(d)))

function _factor_latex(f::Factor)
    if f.base isa ConstMatrix
        t = _const_latex(f.base)
        return f.transposed ? (endswith(t, "^{+}") ? t[1:(end - 1)] * "\\top}" : t * "^{\\top}") : t
    end
    f.base isa Kron && return "\\left(" * _matexpr_latex(f.base.A) * " \\otimes " * _matexpr_latex(f.base.B) * "\\right)"
    if f.base isa MatExpr
        b = "\\left(" * _matexpr_latex(f.base) * "\\right)"
    else
        b = _symbol_latex(f.base)
        b = occursin(r"[_^ ]", b) ? "{" * b * "}" : b
    end
    orthogonal = f.base isa MatrixSymbol && _has(f.base, :orthogonal)
    if orthogonal && f.power < 0
        return f.power == -1 ? b * "^{\\top}" : "\\left(" * b * "^{\\top}\\right)^{" * string(-f.power) * "}"
    end
    sup = f.transposed ? (f.power == 1 ? "\\top" : f.power == -1 ? "-\\top" : "") : (f.power == 1 ? "" : string(f.power))
    f.transposed && abs(f.power) > 1 && return "\\left(" * b * "^{\\top}\\right)^{" * string(f.power) * "}"
    return isempty(sup) ? b : b * "^{" * sup * "}"
end

function _matexpr_latex(A::MatExpr)
    isempty(A.terms) && return "0"
    out = ""
    for (i, (w, c)) in enumerate(A.terms)
        sign, term = _term_latex(w, c)
        out *= i == 1 ? (sign < 0 ? "-" * term : term) : (sign < 0 ? " - " * term : " + " * term)
    end
    return out
end

# a coefficient that is a sum: a `+` or `-` in its text other than a leading sign, outside brackets
function _is_sum_text(s::AbstractString)
    depth = 0
    for (k, ch) in enumerate(s)
        ch in ('(', '[') ? (depth += 1) : ch in (')', ']') ? (depth -= 1) :
        (depth == 0 && k > 1 && ch in ('+', '-')) && return true
    end
    return false
end

# A term as its sign and its written form: the coefficient (from GIAC's `latex`, in parentheses if
# it is a sum) before the product. A term that is only a Kronecker product needs no parentheses:
# ⊗ binds tighter than +.
function _term_latex(w::Word, c::GiacExpr)
    word = isempty(w) ? "I" : join(map(_factor_latex, w), " ")
    sign = 1
    if startswith(string(c), "-")
        n = Commands.normal(-c)
        startswith(string(n), "-") || ((sign, c) = (-1, n))
    end
    cs = string(c)
    if cs == "1"
        length(w) == 1 && w[1].base isa Kron && (word = chop(word; head = 6, tail = 7))
        return (sign, word)
    end
    tex = _scalar_latex(c)
    _is_sum_text(cs) && (tex = "\\left(" * tex * "\\right)")
    return (sign, tex * " " * word)
end

Base.show(io::IO, ::MIME"text/latex", A::MatExpr) = print(io, "\$\$", _matexpr_latex(A), "\$\$")

# ---------------------------------------------------------------------------------------------
# Scalars from matrices: trace and determinant
# ---------------------------------------------------------------------------------------------

# A trace or determinant that does not reduce further (tr(AB), det A, det(A + B)) is a scalar
# variable of its own, named in this registry, so it combines with other scalars in Giac:
# tr(AB) + tr(BA) is 2tr(AB). Its name shows as what it stands for.
const _ATOMS = Dict{String, Tuple{Symbol, Any, String, String}}()   # name => (kind, payload, plain, LaTeX)
const _ATOM_BY_KEY = Dict{String, String}()
const _ATOMS_LOCK = ReentrantLock()

function _atom(kind::Symbol, payload, plain::String, tex::String)
    # the printed form does not show sizes or properties, and a name can be declared again with
    # others: they are part of what the atom stands for
    key = string(kind) * ":" * plain * "|" * join(sort!([string(s.name, ":", s.rows, "×", s.cols, ":", join(s.properties, ","))
                                                          for s in _symbols_in(payload)]), ";")
    name = lock(_ATOMS_LOCK) do
        get!(_ATOM_BY_KEY, key) do
            n = "mxat" * string(length(_ATOMS) + 1)
            _ATOMS[n] = (kind, payload, plain, tex)
            n
        end
    end
    return _matsym_identifier(name)
end

# A product that is 1×1 (vᵀA⁻¹u) is its own trace and is written as itself.
function _trace_atom(w::Word)
    scalar = _rows(first(w)) == 1 && _cols(last(w)) == 1
    plain = join(map(_plain_factor, w), "*")
    tex = join(map(_factor_latex, w), " ")
    return _atom(:tr, w, scalar ? "(" * plain * ")" : "tr(" * plain * ")",
                 scalar ? "\\left(" * tex * "\\right)" : "\\operatorname{tr}\\left(" * tex * "\\right)")
end
_det_atom(b::MatrixSymbol) = _atom(:det, b, "det(" * string(b.name) * ")", "\\det " * _symbol_latex(b))
_det_atom(M::MatExpr) = _atom(:det, M, "det(" * _plain(M) * ")", "\\det\\left(" * _matexpr_latex(M) * "\\right)")

# the matrix atoms' names in LaTeX and in plain text, as what they stand for
function _atom_tex(s::AbstractString)
    occursin("mxat", s) || return s
    return lock(_ATOMS_LOCK) do
        replace(s, r"\\mathrm\{(mxat\d+)\}" => m -> begin
            name = chop(m; head = 8, tail = 1)
            haskey(_ATOMS, name) ? "{" * _ATOMS[name][4] * "}" : m
        end)
    end
end
function _atom_plain(s::AbstractString)
    occursin("mxat", s) || return s
    return lock(() -> replace(s, r"\bmxat\d+\b" => m -> haskey(_ATOMS, m) ? _ATOMS[m][3] : m), _ATOMS_LOCK)
end

_dim_expr(d::Dim) = d isa Int ? convert(GiacExpr, d) : _matsym_identifier(string(d))

"""
    tr(A::MatExpr)

The trace, a scalar: linear, `tr(I) = n`, and the same for every cyclic rotation of a product and
for its transpose (`tr(ABC) = tr(CAB) = tr(CᵀBᵀAᵀ)`), so a product is written in one chosen
rotation. A product that is its own transpose with a sign of -1 (`tr(W)` for a skew `W`) is 0.
"""
function LinearAlgebra.tr(A::MatExpr)
    _square_check(A)
    s = zero(GiacExpr)
    for (w, c) in A.terms
        s += c * _trace_word(w, A.rows)
    end
    return Commands.normal(s)
end

function _trace_word(w::Word, n::Dim)
    sign, cw = _cyclic_canonical(w)
    sign == 0 && return zero(GiacExpr)
    v = isempty(cw) ? _dim_expr(n) :
        length(cw) == 1 && cw[1].base isa Kron ? tr(cw[1].base.A) * tr(cw[1].base.B) :     # tr(A⊗B) = tr A tr B
        length(cw) == 1 && _is_const(cw[1], :commutation) ? _dim_expr(cw[1].base.a) :    # tr K(n,n) = n
        _trace_atom(cw)
    return sign == 1 ? v : -v
end

# shorter first, then a rotation that is 1×1 (a scalar product, vᵀA⁻¹u), then by the word's order
_trace_rank(w::Word) = (length(w), _rows(first(w)) == 1 && _cols(last(w)) == 1 ? 0 : 1, _word_rank(w))

# The rotation of `w` (or of its transpose) that comes first, with its sign; rotating can bring
# a factor next to its inverse, so this repeats until the word stops getting shorter. Sign 0 if the
# word equals minus itself.
function _cyclic_canonical(w::Word)
    sign, w = _normalize(w)
    isempty(w) && return (sign, w)
    while true
        best = (sign, w)
        signs = Dict{String, Int}()
        for k in 0:(length(w) - 1)
            s, r = _normalize(vcat(w[(k + 1):end], w[1:k]))
            ts, tr_ = _transpose_word(r)
            for (cs, cw) in ((sign * s, r), (sign * s * ts, tr_))
                key = _word_key(cw)
                signs[key] = haskey(signs, key) && signs[key] != cs ? 0 : cs
                _trace_rank(cw) < _trace_rank(best[2]) && (best = (cs, cw))
            end
        end
        signs[_word_key(best[2])] == 0 && return (0, best[2])
        length(best[2]) == length(w) && return (best[1], best[2])
        sign, w = best
    end
end

"""
    det(A::MatExpr)

The determinant, a scalar: for a product of square factors, `det(cAB) = cⁿ det A det B`, with
`det Aᵀ = det A`, `det A⁻¹ = 1/det A`, `det Q = ±1` for an orthogonal `Q` (recorded as
`(det Q)² = 1`) and `det W = 0` for a skew `W` of odd size. Anything else is kept whole.
"""
function LinearAlgebra.det(A::MatExpr)
    _square_check(A)
    isempty(A.terms) && return zero(GiacExpr)
    if length(A.terms) == 1
        w, c = only(A.terms)
        if all(f -> _rows(f) == _cols(f), w)
            d = c^_dim_expr(A.rows)
            for f in w
                d *= _det_factor(f)
            end
            return Commands.normal(d)
        end
    end
    return _det_atom(A)
end

function _det_factor(f::Factor)
    b = f.base
    # det(A⊗B) = det(A)ᵐ det(B)ⁿ for A n×n, B m×m
    b isa Kron && return det(b.A)^_dim_expr(b.B.rows) * det(b.B)^_dim_expr(b.A.rows)
    # a commutation matrix permutes: det K(m,n) = (-1)^(m(m-1)n(n-1)/4)
    b isa ConstMatrix && return _commutation_sign(b.a, b.b)^f.power
    b isa MatExpr && return _det_atom(b)^f.power
    _has(b, :orthogonal) && return isodd(f.power) ? _det_atom(b) : one(GiacExpr)
    _has(b, :skew) && b.rows isa Int && isodd(b.rows) && return zero(GiacExpr)
    return _det_atom(b)^f.power
end

# ---------------------------------------------------------------------------------------------
# Declaring symbols
# ---------------------------------------------------------------------------------------------

"""
    @matsym A[n, n] P[n, n]::posdef Q[n, n]::orthogonal x[n] B[n, m]

Declare symbolic matrices: each name is bound to a [`MatExpr`](@ref) standing for a matrix of the
given size, whose products do not commute. A size is a number, a name (`n`; use `\$k` for the
value of a Julia variable `k`), or a product of them (`m*n`, the size of a Kronecker product);
`x[n]` is an `n × 1` column. Tags after `::` (or a tuple of them)
are properties: `symmetric`, `skew`, `diagonal` (symmetric), `orthogonal`, `posdef` and `negdef`
(symmetric and invertible), `invertible`.

The algebra of matrices holds as expressions are built: `(A*B)' == B'*A'`, `inv(A*B) == inv(B)*inv(A)`,
`P' == P`, `Q'*Q == I`, `x'*A'*P*x + x'*P*A*x == 2*x'*P*A*x` (a 1×1 term is its transpose). `tr` and
`det` give scalars (`tr(A*B) == tr(B*A)`), `det Q = ±1` for an orthogonal `Q`, `det W = 0` for a
skew `W` of odd size. `substitute(M, A => entries, …)` gives the explicit matrix; [`differential`](@ref), `∇`, `jacobian`, `hessian` and [`derivative`](@ref)
do matrix calculus, and [`quadratic_form`](@ref) takes a quadratic form apart; `[A B; C D]` is a
block matrix with products, `inv` and `det`.
"""
macro matsym(args...)
    isempty(args) && throw(ArgumentError("@matsym needs a declaration such as A[n, n]"))
    code = Expr[]
    names = Symbol[]
    for arg in args
        spec, tag = arg isa Expr && arg.head === :(::) ? (arg.args[1], arg.args[2]) : (arg, nothing)
        (spec isa Expr && spec.head === :ref && spec.args[1] isa Symbol && 2 <= length(spec.args) <= 3) ||
            throw(ArgumentError("@matsym expects declarations like A[n, n] or x[n], got $spec"))
        name = spec.args[1]
        dims = Any[_size_code(d) for d in spec.args[2:end]]
        length(dims) == 1 && push!(dims, 1)
        tags = tag === nothing ? Symbol[] : tag isa Symbol ? [tag] :
               tag isa Expr && tag.head === :tuple && all(a -> a isa Symbol, tag.args) ? collect(Symbol, tag.args) :
               throw(ArgumentError("@matsym: properties are names, got $tag"))
        push!(code, :($(esc(name)) = _declare_matsym($(QuoteNode(name)), $(dims...), $(Tuple(tags)))))
        push!(names, name)
    end
    return Expr(:block, code..., Expr(:tuple, map(esc, names)...))
end

# a size in a declaration as code: a number, a name, `\$value`, or a product of them (`m*n`)
function _size_code(d)
    d isa Integer && return d
    d isa Symbol && return QuoteNode(d)
    d isa Expr && d.head === :$ && return esc(d.args[1])
    d isa Expr && d.head === :call && d.args[1] === :* && return :(reduce($(GlobalRef(@__MODULE__, :_dim_mul)), ($(map(_size_code, d.args[2:end])...),)))
    throw(ArgumentError("@matsym: a size is a number, a name, \$value, or a product of them; got $d"))
end

function _declare_matsym(name::Symbol, rows, cols, props::Tuple)
    rows, cols = _as_dim(rows), _as_dim(cols)
    for p in props
        p in _MATRIX_SYMBOL_PROPERTIES ||
            throw(ArgumentError("unknown property `$p`; use one of $(join(_MATRIX_SYMBOL_PROPERTIES, ", "))"))
        rows == cols || throw(ArgumentError("$name is $(rows)×$(cols), so it cannot be $p"))
    end
    # (the ergonomics branch also records here what is known of its trace and determinant, det P > 0,
    # (det Q)² = 1, for the sign tests of its rules engine, which is not ported)
    return MatExpr(MatrixSymbol(name, rows, cols, collect(Symbol, props)))
end

_as_dim(d::Integer) = Int(d)
_as_dim(d::Symbol) = d
_as_dim(d) = throw(ArgumentError("a size is an integer or a name, got $d"))

# the symbol an expression stands for, if it is a lone symbol
function _symbol_of(M::MatExpr)
    length(M.terms) == 1 || return nothing
    w, c = only(M.terms)
    (string(c) == "1" && length(w) == 1 && only(w).base isa MatrixSymbol && !only(w).transposed && only(w).power == 1) || return nothing
    return only(w).base
end

# ---------------------------------------------------------------------------------------------
# Explicit matrices
# ---------------------------------------------------------------------------------------------

"""
    substitute(M::MatExpr, A => Aentries, B => Bentries, …) -> Matrix{GiacExpr}
    substitute(e::GiacExpr, A => Aentries, …)

The explicit matrix (or scalar) for given entries of every symbol in `M` (from `@giac_matrix`,
numbers, …). Size names take the sizes given: with `A[n, n]` and a 2×2 `Aentries`, `n` is 2.
"""
function substitute(M::MatExpr, pair::Pair{MatExpr, <:AbstractMatrix}, pairs::Pair{MatExpr, <:AbstractMatrix}...)
    values, dims = _matrix_values((pair, pairs...))
    return _evaluate(M, values, dims)
end

function substitute(e::GiacExpr, pair::Pair{MatExpr, <:AbstractMatrix}, pairs::Pair{MatExpr, <:AbstractMatrix}...)
    values, dims = _matrix_values((pair, pairs...))
    return _evaluate_scalar(e, values, dims)
end

function _matrix_values(pairs)
    values = Dict{Symbol, Matrix{GiacExpr}}()
    dims = Dict{Symbol, Int}()
    bind(d::Int, k) = d == k || throw(DimensionMismatch("a size $d given $k"))
    bind(d::Symbol, k) = get!(dims, d, k) == k || throw(DimensionMismatch("$d is $(dims[d]) and $k"))
    for (k, v) in pairs
        s = _symbol_of(k)
        s === nothing && throw(ArgumentError("substitute: $(_plain(k)) is not a single matrix symbol"))
        bind(s.rows, size(v, 1)); bind(s.cols, size(v, 2))
        values[s.name] = GiacExpr[convert(GiacExpr, x) for x in v]
    end
    return values, dims
end

_dim_value(d::Int, dims) = d
function _dim_value(d::Symbol, dims)
    v = _dim_eval(Meta.parse(string(d)), dims)
    isinteger(v) || throw(ArgumentError("the size $d is not an integer"))
    return Int(v)
end

# a size expression with the sizes of names given, in exact arithmetic
_dim_eval(x::Integer, dims) = Rational{Int}(x)
_dim_eval(x::Symbol, dims) = haskey(dims, x) ? Rational{Int}(dims[x]) : throw(ArgumentError("no size given for $x"))
function _dim_eval(x::Expr, dims)
    (x.head === :call && x.args[1] in (:+, :-, :*, :/)) || throw(ArgumentError("a size is an integer expression, got $x"))
    v = map(a -> _dim_eval(a, dims), x.args[2:end])
    op = x.args[1] === :/ ? (//) : getfield(Base, x.args[1])
    return op(v...)
end

function _commutation_sign(m::Dim, n::Dim)
    (m isa Int && n isa Int) || return _det_atom(_matexpr(_dim_mul(m, n), _dim_mul(m, n), [Factor[Factor(ConstMatrix(:commutation, m, n), false, 1)] => one(GiacExpr)]))
    return convert(GiacExpr, isodd(m * (m - 1) * n * (n - 1) ÷ 4) ? -1 : 1)
end

# the entries of a commutation or duplication matrix, for numbers given for its sizes
function _const_value(b::ConstMatrix, dims)
    o, z = one(GiacExpr), zero(GiacExpr)
    if b.kind === :commutation
        m, n = _dim_value(b.a, dims), _dim_value(b.b, dims)
        K = fill(z, m * n, m * n)
        for i in 1:m, j in 1:n
            K[j + (i - 1) * n, i + (j - 1) * m] = o        # vec(Xᵀ)[(i,j)ᵀ] = vec(X)[(i,j)]
        end
        return K
    end
    n = _dim_value(b.a, dims)
    plus = b.kind === :duplication_plus
    half = convert(GiacExpr, 1 // 2)
    M = plus ? fill(z, n * (n + 1) ÷ 2, n * n) : fill(z, n * n, n * (n + 1) ÷ 2)
    k = 0
    for j in 1:n, i in j:n                               # vech: the lower triangle, by columns
        k += 1
        p, q = i + (j - 1) * n, j + (i - 1) * n          # the places of (i,j) and (j,i) in vec
        if plus
            # D⁺ = (DᵀD)⁻¹Dᵀ: a diagonal entry read once, an off-diagonal one averaged
            i == j ? (M[k, p] = o) : (M[k, p] = half; M[k, q] = half)
        else
            M[p, k] = o
            M[q, k] = o
        end
    end
    return M
end

function _evaluate(M::MatExpr, values, dims)
    m, n = _dim_value(M.rows, dims), _dim_value(M.cols, dims)
    R = fill(zero(GiacExpr), m, n)
    for (w, c) in M.terms
        P = isempty(w) ? GiacExpr[i == j ? one(GiacExpr) : zero(GiacExpr) for i in 1:m, j in 1:m] :
                         _word_matrix(w, values, dims)
        R = R + _evaluate_scalar(c, values, dims) * P
    end
    return map(e -> invoke_cmd(:regroup, e), R)      # like terms collected, nothing expanded
end

# the matrix of a (nonempty) word
_word_matrix(w::Word, values, dims) = reduce(*, (_factor_value(f, values, dims) for f in w))

function _factor_value(f::Factor, values, dims)
    if f.base isa ConstMatrix
        M = _const_value(f.base, dims)
        return f.transposed ? permutedims(M) : M
    end
    f.base isa Kron && return kron(_evaluate(f.base.A, values, dims), _evaluate(f.base.B, values, dims))
    B = f.base isa MatExpr ? _evaluate(f.base, values, dims) :
        haskey(values, f.base.name) ? values[f.base.name] :
        throw(ArgumentError("substitute: no entries given for $(f.base.name)"))
    f.transposed && (B = permutedims(B))
    f.power < 0 && (B = inv(B))
    R = B
    for _ in 2:abs(f.power)
        R = R * B
    end
    return R
end

function _evaluate_scalar(e::GiacExpr, values, dims)
    subs = Dict{GiacExpr, Any}()
    for v in free_symbols(e)
        name = string(v)
        if haskey(_ATOMS, name)
            kind, payload = _ATOMS[name]
            subs[v] = kind === :tr ? sum(LinearAlgebra.diag(_word_matrix(payload, values, dims))) :
                      LinearAlgebra.det(payload isa MatrixSymbol ? _factor_value(Factor(payload, false, 1), values, dims) :
                                                                   _evaluate(payload, values, dims))
        elseif haskey(dims, Symbol(name))
            subs[v] = dims[Symbol(name)]
        end
    end
    return isempty(subs) ? e : substitute(e, subs)
end

# ---------------------------------------------------------------------------------------------
# Quadratic and linear forms
# ---------------------------------------------------------------------------------------------

_is_symbol(f::Factor, x::MatrixSymbol) = f.base isa MatrixSymbol && f.base == x && f.power == 1

# The parts of a 1×1 term in a vector `x`: `(:quadratic, W)` for xᵀWx, `(:linear, b)` for xᵀb or
# bᵀx (as the column b), `(:constant, nothing)` without `x`.
function _form_part(w::Word, x::MatrixSymbol)
    at = findall(f -> f.base isa MatrixSymbol && f.base == x, w)
    isempty(at) && return (:constant, nothing)
    all(i -> _is_symbol(w[i], x), at) ||
        throw(ArgumentError("$(x.name) appears other than as $(x.name) or $(x.name)ᵀ in $(join(map(_plain_factor, w), "*"))"))
    rest(r) = isempty(r) ? identity_matrix(x.rows) : _matexpr(_rows(first(r)), _cols(last(r)), [r => one(GiacExpr)])
    if length(at) == 2 && at == [1, length(w)] && w[1].transposed && !w[end].transposed
        return (:quadratic, rest(w[2:(end - 1)]))
    elseif length(at) == 1 && at[1] == 1 && w[1].transposed
        return (:linear, rest(w[2:end]))
    elseif length(at) == 1 && at[1] == length(w) && !w[end].transposed
        return (:linear, transpose(rest(w[1:(end - 1)])))
    end
    throw(ArgumentError("$(join(map(_plain_factor, w), "*")) is not a linear or quadratic form in $(x.name)"))
end

function _vector_symbol(x::MatExpr)
    s = _symbol_of(x)
    (s === nothing || s.cols != 1) && throw(ArgumentError("$(_plain(x)) is not a vector symbol (declare one with @matsym x[n])"))
    return s
end

"""
    quadratic_form(f, x) -> MatExpr

The symmetric `S` with `f = xᵀSx`, for a scalar expression `f` quadratic in the vector `x`: for
`V̇ = xᵀAᵀPx + xᵀPAx` it is `AᵀP + PA`, the matrix of a Lyapunov equation. Terms that are not
quadratic in `x` are an error.
"""
function quadratic_form(f::MatExpr, x::MatExpr)
    (f.rows == 1 && f.cols == 1) || throw(DimensionMismatch("quadratic_form takes a scalar (1×1) expression"))
    s = _vector_symbol(x)
    S = zero_matrix(s.rows, s.rows)
    for (w, c) in f.terms
        kind, part = _form_part(w, s)
        kind === :quadratic || throw(ArgumentError("$(_plain(f)) has a term that is not quadratic in $(s.name)"))
        S = S + (c / 2) * (part + transpose(part))
    end
    return S
end

# ---------------------------------------------------------------------------------------------
# Block matrices: arrays of expressions
# ---------------------------------------------------------------------------------------------

# `[A B; C D]` with symbolic blocks is a Matrix{MatExpr}. A block `I` or `0` takes its size from
# the blocks in its row and column.
const _Block = Union{MatExpr, UniformScaling, Number}

function _blocks(rows::Tuple{Vararg{Int}}, xs)
    nr, nc = length(rows), first(rows)
    all(==(nc), rows) || throw(ArgumentError("block rows have different numbers of blocks"))
    grid = permutedims(reshape(collect(Any, xs), nc, nr))
    height(i) = (k = findfirst(x -> x isa MatExpr, grid[i, :])) === nothing ? nothing : grid[i, k].rows
    width(j) = (k = findfirst(x -> x isa MatExpr, grid[:, j])) === nothing ? nothing : grid[k, j].cols
    return MatExpr[_block(grid[i, j], height(i), width(j), i, j) for i in 1:nr, j in 1:nc]
end

# a block as an expression: `I` and `0` sized by their row's height `h` and column's width `w`
function _block(x, h, w, i, j)
    x isa MatExpr && return x
    (h === nothing || w === nothing) && throw(ArgumentError("no block in row $i or column $j to give the size of $x"))
    if x isa UniformScaling
        h == w || throw(DimensionMismatch("I in a $(h)×$(w) block"))
        return _coefficient(x.λ) * identity_matrix(h)
    end
    iszero(x) || throw(ArgumentError("a number block must be 0, got $x"))
    return zero_matrix(h, w)
end

Base.hvcat(rows::Tuple{Vararg{Int}}, a::MatExpr, xs::_Block...) = _blocks(rows, (a, xs...))
Base.hvcat(rows::Tuple{Vararg{Int}}, a::Union{UniformScaling, Number}, b::MatExpr, xs::_Block...) = _blocks(rows, (a, b, xs...))
Base.hvcat(rows::Tuple{Vararg{Int}}, a::Union{UniformScaling, Number}, b::Union{UniformScaling, Number}, c::MatExpr, xs::_Block...) =
    _blocks(rows, (a, b, c, xs...))
Base.hcat(a::MatExpr, xs::_Block...) = _blocks((1 + length(xs),), (a, xs...))
Base.vcat(a::MatExpr, xs::_Block...) = _blocks(ntuple(_ -> 1, 1 + length(xs)), (a, xs...))

function Base.:*(X::AbstractMatrix{MatExpr}, Y::AbstractMatrix{MatExpr})
    size(X, 2) == size(Y, 1) || throw(DimensionMismatch("block product of $(size(X)) and $(size(Y)) blocks"))
    return MatExpr[reduce(+, (X[i, k] * Y[k, j] for k in axes(X, 2))) for i in axes(X, 1), j in axes(Y, 2)]
end
Base.:*(X::AbstractMatrix{MatExpr}, Y::AbstractVector{MatExpr}) = vec(X * reshape(Y, :, 1))
Base.:*(c::Number, X::AbstractArray{MatExpr}) = map(B -> c * B, X)
Base.:*(c::GiacExpr, X::AbstractArray{MatExpr}) = map(B -> c * B, X)
Base.transpose(X::AbstractMatrix{MatExpr}) = permutedims(map(transpose, X))
Base.adjoint(X::AbstractMatrix{MatExpr}) = transpose(X)

"""
    inv(X::Matrix{MatExpr})

The inverse of a 2×2 block matrix `[A B; C D]`, by the Schur complement `S = D - CA⁻¹B` of an
invertible `A`: `[A⁻¹ + A⁻¹BS⁻¹CA⁻¹  -A⁻¹BS⁻¹; -S⁻¹CA⁻¹  S⁻¹]`.
"""
Base.inv(X::AbstractMatrix{MatExpr}) = _block_inv(X)
Base.inv(X::StridedMatrix{MatExpr}) = _block_inv(X)      # before LinearAlgebra's method for strided arrays
function _block_inv(X)
    size(X) == (2, 2) || throw(ArgumentError("inv of block matrices is for 2×2 blocks"))
    A, B, C, D = X[1, 1], X[1, 2], X[2, 1], X[2, 2]
    Ai = inv(A)
    Si = inv(D - C * Ai * B)
    return MatExpr[Ai+Ai*B*Si*C*Ai -Ai*B*Si; -Si*C*Ai Si]
end

"`det([A B; C D]) = det(A) det(D - CA⁻¹B)` for an invertible `A`."
function LinearAlgebra.det(X::AbstractMatrix{MatExpr})
    size(X) == (2, 2) || throw(ArgumentError("det of block matrices is for 2×2 blocks"))
    A, B, C, D = X[1, 1], X[1, 2], X[2, 1], X[2, 2]
    return Commands.normal(LinearAlgebra.det(A) * LinearAlgebra.det(D - C * inv(A) * B))
end

function _blocks_latex(X::AbstractVecOrMat{MatExpr})
    rows = [join((_matexpr_latex(X[i, j]) for j in axes(X, 2)), " & ") for i in axes(X, 1)]
    return "\\begin{bmatrix}" * join(rows, " \\\\ ") * "\\end{bmatrix}"
end
Base.show(io::IO, ::MIME"text/latex", X::AbstractVecOrMat{MatExpr}) = print(io, "\$\$", _blocks_latex(X), "\$\$")

"`A` with `f` applied to each coefficient (to simplify them, say), terms combined again."
map_coefficients(f, A::MatExpr) = _matexpr(A.rows, A.cols, [w => convert(GiacExpr, f(c)) for (w, c) in A.terms])

# the matrix symbols in an atom's payload: a symbol, a word, or an expression
_symbols_in(s::MatrixSymbol) = [s]
_symbols_in(k::Kron) = unique(s -> s.name, vcat(_symbols_in(k.A), _symbols_in(k.B)))
_symbols_in(::ConstMatrix) = MatrixSymbol[]
_symbols_in(w::Word) = unique(s -> s.name, reduce(vcat, (_symbols_in(f.base) for f in w); init = MatrixSymbol[]))
_symbols_in(M::MatExpr) = unique(s -> s.name, reduce(vcat, (_symbols_in(w) for (w, _) in M.terms); init = MatrixSymbol[]))
