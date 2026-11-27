# Matrix calculus with differentials: d(XY) = dX Y + X dY, d(Xᵏ) = Σ Xʲ dX Xᵏ⁻¹⁻ʲ,
# d(X⁻¹) = -X⁻¹ dX X⁻¹, d tr W = tr dW, d det M = det M tr(M⁻¹ dM). A gradient is read off
# df = Σ tr(U dX V) = Σ tr(VU dX), a Jacobian off dF = J dx.
#
# Ported from Kahli Burke's `ergonomics` branch (src/matrix_calculus.jl, and `differential` from
# src/differentials.jl). ∇, jacobian and hessian are those of array_algebra.jl, given methods for
# matrix symbols here.

# The differential of a symbol: a symbol of the same size, written dX, with the structure that
# survives differentiation (a symmetric matrix has a symmetric differential)
function _dsym(s::MatrixSymbol)
    name = Symbol("d", s.name)
    _record_matsym_tex!(string(name), "\\mathrm{d}" * _matsym_tex(string(s.name)))
    props = filter(p -> p in (:symmetric, :skew, :diagonal), s.properties)
    _symmetric(s) && !(:symmetric in props) && !(:diagonal in props) && push!(props, :symmetric)
    return MatrixSymbol(name, s.rows, s.cols, props)
end

_varies(s::MatrixSymbol, vary) = vary === nothing || s.name in vary

# a word as an expression, or the identity of size `n` if it is empty
_word_expr(w::Word, n::Dim) = isempty(w) ? identity_matrix(n) : _matexpr(_rows(first(w)), _cols(last(w)), [w => one(GiacExpr)])

"""
    differential(M, X, Y, …)
    differential(M)
    differential(f, x, y, …)
    differential(x)

The differential of a matrix expression, or of a scalar, in the variables given, or in all of its
variables when none are given:

- a matrix expression, or a scalar made of traces and determinants, in matrix symbols declared
  with [`@matsym`](@ref), in terms of their differentials `dX`: `d(XY) = dX Y + X dY`,
  `d(X⁻¹) = -X⁻¹ dX X⁻¹`, `d tr W = tr dW`, `d det M = det M tr(M⁻¹ dM)`. The symbols not given
  are constants.
- a scalar in scalar variables is `∂f/∂x dx + ∂f/∂y dy + …`, each `dx` a variable of its own;
  `differential(x)` of a variable alone is its `dx`.

Scalar variables and matrix symbols can be mixed.

```julia
@matsym X[n, n] A[n, n] x[n]
differential(inv(X))          # -X⁻¹ dX X⁻¹
differential(tr(A*X), X)      # tr(A dX)
differential(x'*A*x, x)       # dxᵀAx + xᵀA dx

@giac_var u
differential(u^2 + tr(A*X), u, X)      # 2u du + tr(A dX)
```

[`∇`](@ref), `jacobian`, `hessian` and [`derivative`](@ref) are read off the differential.
"""
differential(M::MatExpr, symbols::MatExpr...) = _differential(M, _vary_set(symbols))

# The scalar side, simpler than the ergonomics branch's (src/differentials.jl), which is built on
# its unported `partial` and tree engine: here ∂f/∂x is GIAC's `diff`, a variable is an identifier
# (not a function of time q(t)), and the variables of `f` are its free symbols, the traces and
# determinants of matrices left out.
function differential(f::GiacExpr, vars::Union{GiacExpr, MatExpr}...)
    if isempty(vars)
        # a variable alone is its differential, dx
        is_identifier(f) && !_is_matrix_atom(f) && return _matsym_identifier("d" * string(f))
        scalars = GiacExpr[v for v in collect(GiacExpr, free_symbols(f)) if !_is_matrix_atom(v)]
        return _total_differential(f, scalars, nothing)
    end
    scalars = GiacExpr[v for v in vars if v isa GiacExpr]
    for v in scalars
        is_identifier(v) || throw(ArgumentError("differential: a scalar variable is an identifier, got $v"))
    end
    matrices = [v for v in vars if v isa MatExpr]
    return _total_differential(f, scalars, isempty(matrices) ? Set{Symbol}() : _vary_set(matrices))
end

# ∂f/∂x dx summed over the scalar variables, and the matrix part over `vary` (nothing: every
# matrix symbol; an empty set: none)
function _total_differential(f::GiacExpr, scalars::Vector{GiacExpr}, vary)
    d = zero(GiacExpr)
    for v in scalars
        d += Commands.diff(f, v) * differential(v)
    end
    (vary === nothing || !isempty(vary)) && (d += _differential(f, vary))
    return d
end

_is_matrix_atom(x::GiacExpr) = is_identifier(x) && lock(() -> haskey(_ATOMS, string(x)), _ATOMS_LOCK)

_vary_set(symbols) = isempty(symbols) ? nothing : Set(_matrix_symbol(X).name for X in symbols)

function _matrix_symbol(X::MatExpr)
    s = _symbol_of(X)
    s === nothing && throw(ArgumentError("$(_plain(X)) is not a matrix symbol (declare one with @matsym)"))
    return s
end

function _differential(M::MatExpr, vary)
    D = zero_matrix(M.rows, M.cols)
    for (w, c) in M.terms
        for i in eachindex(w)
            dF = _dfactor(w[i], vary)
            dF === nothing && continue
            D = D + c * (_word_expr(w[1:(i - 1)], _rows(w[i])) * dF * _word_expr(w[(i + 1):end], _cols(w[i])))
        end
        dc = _differential(c, vary)
        _iszero_coefficient(dc) || (D = D + dc * _word_expr(w, M.rows))
    end
    return D
end

function _dfactor(f::Factor, vary)
    B = f.base
    B isa ConstMatrix && return nothing                 # a constant
    if B isa Kron
        # d(A⊗B) = dA⊗B + A⊗dB (a Kronecker factor is untransposed, to the first power)
        dA, dB = _differential(B.A, vary), _differential(B.B, vary)
        D = kron(dA, B.B) + kron(B.A, dB)
        return iszero(D) ? nothing : D
    end
    if B isa MatrixSymbol
        _varies(B, vary) || return nothing
        X, dX = MatExpr(B), MatExpr(_dsym(B))
    else
        X, dX = B, _differential(B, vary)
        iszero(dX) && return nothing
    end
    Y, dY = f.power > 0 ? (X, dX) : (inv(X), -(inv(X) * dX * inv(X)))
    m = abs(f.power)
    D = m == 1 ? dY : reduce(+, (Y^j * dY * Y^(m - 1 - j) for j in 0:(m - 1)))
    return f.transposed ? transpose(D) : D
end

# the traces and determinants a scalar is written in
# (the ergonomics branch walks its expression tree for the names; here they are GIAC's `lname`)
function _atoms_in(c::GiacExpr)
    names = String[string(v) for v in collect(GiacExpr, free_symbols(c))]
    return lock(() -> [a for a in names if haskey(_ATOMS, a)], _ATOMS_LOCK)
end

function _differential(c::GiacExpr, vary)
    d = zero(GiacExpr)
    for a in _atoms_in(c)
        da = _datom(a, vary)
        da === nothing || (d += Commands.diff(c, _matsym_identifier(a)) * da)
    end
    return d
end

function _datom(name::String, vary)
    kind, payload, _, _ = lock(() -> _ATOMS[name], _ATOMS_LOCK)
    if kind === :tr
        dW = _differential(_word_expr(payload, 0), vary)
        return iszero(dW) ? nothing : tr(dW)
    end
    M = payload isa MatrixSymbol ? MatExpr(payload) : payload
    dM = _differential(M, vary)
    return iszero(dM) ? nothing : _matsym_identifier(name) * tr(inv(M) * dM)
end

# ---------------------------------------------------------------------------------------------
# Gradients, Jacobians, Hessians
# ---------------------------------------------------------------------------------------------

# The gradient that the trace atom `name` contributes for the differential symbol `ds` of `s`:
# tr(U dX V) = tr(VU dX) gives (VU)ᵀ, tr(U dXᵀ V) gives VU. `nothing` if dX is not in it.
function _atom_gradient(name::String, ds::MatrixSymbol, s::MatrixSymbol)
    kind, w, _, _ = lock(() -> _ATOMS[name], _ATOMS_LOCK)
    kind === :tr || return nothing
    i = findfirst(f -> f.base isa MatrixSymbol && f.base == ds, w)
    i === nothing && return nothing
    f = w[i]
    U = _word_expr(w[1:(i - 1)], _rows(f))
    V = _word_expr(w[(i + 1):end], _cols(f))
    return f.transposed ? V * U : transpose(V * U)
end

"""
    ∇(f, X)

The gradient of a scalar `f` (a trace, a determinant, a 1×1 expression, or a function of them) in
the matrix or vector symbol `X`: the matrix `G` with `df = tr(Gᵀ dX)`. For `f = xᵀWx + bᵀx + c`
it is `(W + Wᵀ)x + b`; `∇(tr(A*X), X)` is `Aᵀ`, `∇(det(X), X)` is `det(X) X⁻ᵀ`. For a symmetric `X`
this is the gradient over all entries, without the symmetry.
"""
∇(f::MatExpr, X::MatExpr) = ((f.rows == 1 && f.cols == 1) || throw(DimensionMismatch("∇ takes a scalar (1×1) expression"));
                             ∇(tr(f), X))
function ∇(f::GiacExpr, X::MatExpr)
    s = _matrix_symbol(X)
    ds = _dsym(s)
    df = _differential(f, Set([s.name]))
    G = zero_matrix(s.rows, s.cols)
    for a in _atoms_in(df)
        g = _atom_gradient(a, ds, s)
        g === nothing || (G = G + Commands.diff(df, _matsym_identifier(a)) * g)
    end
    return G
end

"""
    jacobian(F, x)

The Jacobian of a vector expression `F` in the vector symbol `x`: the matrix `J` with `dF = J dx`.
`jacobian(A*x, x)` is `A`; `jacobian((x'*x)*b, x)` is `2bxᵀ`.
"""
function jacobian(F::MatExpr, x::MatExpr)
    F.cols == 1 || throw(DimensionMismatch("jacobian takes a column expression"))
    s = _vector_symbol(x)
    ds = _dsym(s)
    dF = _differential(F, Set([s.name]))
    J = zero_matrix(F.rows, s.rows)
    for (w, c) in dF.terms
        i = findfirst(f -> f.base isa MatrixSymbol && f.base == ds, w)
        if i === nothing
            # the coefficient carries the differential: c = Σ kₐ a with a = gₐᵀ dx
            W = _word_expr(w, F.rows)
            for a in _atoms_in(c)
                g = _atom_gradient(a, ds, s)
                g === nothing || (J = J + Commands.diff(c, _matsym_identifier(a)) * W * transpose(g))
            end
        elseif !w[i].transposed
            # U dx V, with V empty or 1×1 (a scalar)
            U = _word_expr(w[1:(i - 1)], F.rows)
            V = w[(i + 1):end]
            J = J + (isempty(V) ? c : c * tr(_word_expr(V, 1))) * U
        else
            # U dxᵀ V = U Vᵀ dx
            U = _word_expr(w[1:(i - 1)], F.rows)
            V = _word_expr(w[(i + 1):end], s.rows)
            J = J + c * U * transpose(V)
        end
    end
    return J
end

"""
    hessian(f, x)

The Hessian of a scalar `f` in the vector symbol `x`, the Jacobian of its gradient: for
`f = xᵀWx` it is `W + Wᵀ`.
"""
hessian(f::Union{GiacExpr, MatExpr}, x::MatExpr) = jacobian(∇(f, x), x)

# ---------------------------------------------------------------------------------------------
# Derivatives along a direction
# ---------------------------------------------------------------------------------------------

"""
    derivative(f, X => Ẋ, …)

The derivative of `f` (a matrix expression or a scalar) when the symbols `X` change at the rates
`Ẋ`: the differential with each `dX` replaced by `Ẋ`. The derivative of a Lyapunov function
along the trajectories of `ẋ = Ax` is `derivative(x'*P*x, x => A*x)`, which is
`xᵀ(AᵀP + PA)x`. Symbols not given are constant.
"""
function derivative(f::Union{MatExpr, GiacExpr}, rates::Pair{MatExpr, MatExpr}...)
    isempty(rates) && throw(ArgumentError("give the rate of change of at least one symbol: X => Ẋ"))
    table = Dict{Symbol, MatExpr}()
    for (X, V) in rates
        s = _matrix_symbol(X)
        size(V) == (s.rows, s.cols) || throw(DimensionMismatch("$(s.name) is $(s.rows)×$(s.cols), its rate $(size(V, 1))×$(size(V, 2))"))
        table[_dsym(s).name] = V
    end
    df = _differential(f, Set(_matrix_symbol(first(p)).name for p in rates))
    return _replace(df, table)
end

# `M` with the symbols in `table` replaced by expressions, in products and in traces
function _replace(M::MatExpr, table)
    R = zero_matrix(M.rows, M.cols)
    for (w, c) in M.terms
        P = _word_expr(Factor[], M.rows)
        for f in w
            P = P * _replace_factor(f, table)
        end
        R = R + _replace(c, table) * P
    end
    return R
end

function _replace_factor(f::Factor, table)
    b = f.base
    V = b isa MatExpr ? _replace(b, table) : get(() -> MatExpr(b), table, b.name)
    V = f.power == 1 ? V : f.power < 0 ? inv(V)^(-f.power) : V^f.power
    return f.transposed ? transpose(V) : V
end

function _replace(c::GiacExpr, table)
    for a in _atoms_in(c)
        kind, payload, _, _ = lock(() -> _ATOMS[a], _ATOMS_LOCK)
        kind === :tr || continue
        any(f -> f.base isa MatrixSymbol && haskey(table, f.base.name), payload) || continue
        c = substitute(c, _matsym_identifier(a) => tr(_replace(_word_expr(payload, 0), table)))
    end
    return c
end
