# Kronecker products and vectorization: vec(UXV) = (Vᵀ ⊗ U) vec X turns a linear matrix
# equation into a linear system, as AᵀP + PA = -Q becomes (I⊗Aᵀ + Aᵀ⊗I) vec P = -vec Q.
# Ported from Kahli Burke's `ergonomics` branch (src/kronecker.jl).

"""
    kron(A::MatExpr, B::MatExpr)

The Kronecker product `A ⊗ B`, of size `(m·p) × (n·q)` for `A` `m × n` and `B` `p × q` (sizes
given by names multiply as names: `n*n`). It is bilinear, `I ⊗ I` is the identity, and the rules
hold as expressions are built: `(A⊗B)(C⊗D) = AC⊗BD`, `(A⊗B)ᵀ = Aᵀ⊗Bᵀ`, `(A⊗B)⁻¹ = A⁻¹⊗B⁻¹`,
`tr(A⊗B) = tr A tr B`, `det(A⊗B) = (det A)ᵐ (det B)ⁿ` for `A` `n × n` and `B` `m × m`.
`substitute` gives the explicit Kronecker product.
"""
function Base.kron(A::MatExpr, B::MatExpr)
    rows, cols = _dim_mul(A.rows, B.rows), _dim_mul(A.cols, B.cols)
    terms = Pair{Word, GiacExpr}[]
    for (wa, ca) in A.terms, (wb, cb) in B.terms
        unit(w, M) = MatExpr(isempty(w) ? M.rows : _rows(first(w)), isempty(w) ? M.cols : _cols(last(w)), [w => one(GiacExpr)])
        sign, f = _kron_factor(unit(wa, A), unit(wb, B))
        push!(terms, (f === nothing ? Factor[] : Factor[f]) => (sign == 1 ? ca * cb : -(ca * cb)))
    end
    return _matexpr(rows, cols, terms)
end
Base.kron(A::MatExpr, J::UniformScaling) = kron(A, _identity_like(J, A.cols))
Base.kron(J::UniformScaling, A::MatExpr) = kron(_identity_like(J, A.rows), A)
_identity_like(J::UniformScaling, n::Dim) = _coefficient(J.λ) * identity_matrix(n)

"""
    vec(X::MatExpr)

The columns of the matrix symbol `X` stacked into one column, written `vec X`: a vector symbol of
size `(m·n) × 1`. Used with [`vectorize`](@ref).
"""
function Base.vec(X::MatExpr)
    s = _matrix_symbol(X)
    s.cols == 1 && return X
    name = Symbol("vec", s.name)
    _record_matsym_tex!(string(name), "\\operatorname{vec} " * _matsym_tex(string(s.name)))
    return MatExpr(MatrixSymbol(name, _dim_mul(s.rows, s.cols), 1, Symbol[]))
end

# a constant structured matrix as an expression
_const_expr(kind, a, b) = (c = ConstMatrix(kind, a, b); _matexpr(_rows(c), _cols(c), [Factor[Factor(c, false, 1)] => one(GiacExpr)]))

"""
    commutation(m, n)

The commutation matrix `K(m,n)`, the `mn × mn` permutation with `vec(Xᵀ) = K(m,n) vec X` for an
`m × n` matrix `X`. As expressions are built, `K(m,n)ᵀ = K(m,n)⁻¹ = K(n,m)`, `K(1,n) = I`,
`K(n,n)D(n) = D(n)`, and a `K` moves past a Kronecker product: `K(p,m)(A⊗B) = (B⊗A)K(q,n)` for
`A` `m × n` and `B` `p × q`. Sizes are numbers or names.
"""
commutation(m, n) = _const_expr(:commutation, _as_dim(m), _as_dim(n))

"""
    duplication(n)

The duplication matrix `D(n)`, `n² × n(n+1)/2`, with `vec P = D(n) vech P` for a symmetric `n × n`
matrix `P`; [`duplication_plus`](@ref) is its left inverse.
"""
duplication(n) = _const_expr(:duplication, _as_dim(n), _as_dim(n))

"""
    duplication_plus(n)

`D(n)⁺ = (DᵀD)⁻¹Dᵀ`, the left inverse of the duplication matrix: `vech P = D⁺ vec P` for a
symmetric `P`, and `D⁺D = I`.
"""
duplication_plus(n) = _const_expr(:duplication_plus, _as_dim(n), _as_dim(n))

"""
    vech(P::MatExpr)

The entries of the symmetric matrix symbol `P` on and below the diagonal, column by column, as one
column of size `n(n+1)/2`, written `vech P`: `vec P = D vech P`.
"""
function vech(P::MatExpr)
    s = _matrix_symbol(P)
    _symmetric(s) || throw(ArgumentError("vech takes a symmetric matrix; declare $(s.name) with ::symmetric"))
    name = Symbol("vech", s.name)
    _record_matsym_tex!(string(name), "\\operatorname{vech} " * _matsym_tex(string(s.name)))
    return MatExpr(MatrixSymbol(name, _vech_dim(s.rows), 1, Symbol[]))
end

"""
    vectorize(E, X) -> (K = …, R = …)
    vectorize(E, P; unknowns = :vech) -> (K = …, R = …)

An expression `E` linear in the matrix symbol `X`, as the linear system its entries make:
`vec E = K vec X + vec R`, with `K` from `vec(UXV) = (Vᵀ ⊗ U) vec X` and `vec(UXᵀV) = (Vᵀ ⊗ U)
K(m,n) vec X` (a [`commutation`](@ref) matrix), and `R` the terms without `X`. The result is a
named tuple: `vectorize(E, X).K`, or `K, R = vectorize(E, X)`.

```julia
@matsym A[n, n] P[n, n]::symmetric
K, R = vectorize(A'*P + P*A, P)       # K = Aᵀ⊗I + I⊗Aᵀ, R = 0
substitute(K, A => [0 1; -2 -3])      # the 4×4 matrix, to solve K vec P = -vec Q
```

For a symmetric unknown `P` and symmetric `E` (a Lyapunov or Riccati-like equation),
`unknowns = :vech` counts each entry once: `vech E = K vech P + vech R` with
`K = D⁺ K₀ D`, square of size `n(n+1)/2`. `X` must appear at most once in each term.
"""
function vectorize(E::MatExpr, X::MatExpr; unknowns::Symbol = :vec)
    unknowns in (:vec, :vech) || throw(ArgumentError("unknowns is :vec or :vech, got :$unknowns"))
    s = _matrix_symbol(X)
    K = zero_matrix(_dim_mul(E.rows, E.cols), _dim_mul(s.rows, s.cols))
    R = zero_matrix(E.rows, E.cols)
    for (w, c) in E.terms
        at = findall(f -> f.base isa MatrixSymbol && f.base == s, w)
        if isempty(at)
            R = R + c * _word_expr(w, E.rows)
            continue
        end
        (length(at) == 1 && w[only(at)].power == 1) ||
            throw(ArgumentError("$(_plain(E, true)) is not linear in $(s.name)"))
        i = only(at)
        U = _word_expr(w[1:(i - 1)], w[i].transposed ? s.cols : s.rows)
        V = _word_expr(w[(i + 1):end], w[i].transposed ? s.rows : s.cols)
        # vec(U Xᵀ V) = (Vᵀ ⊗ U) vec(Xᵀ) = (Vᵀ ⊗ U) K(m,n) vec X
        term = kron(transpose(V), U)
        w[i].transposed && (term = term * commutation(s.rows, s.cols))
        K = K + c * term
    end
    unknowns === :vec && return (K = K, R = R)
    _symmetric(s) || throw(ArgumentError("unknowns = :vech needs a symmetric $(s.name)"))
    (E.rows == E.cols && E == transpose(E)) || throw(ArgumentError("unknowns = :vech needs a symmetric expression"))
    return (K = duplication_plus(E.rows) * K * duplication(s.rows), R = R)
end
