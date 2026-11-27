# Symbolic linear algebra on ordinary Julia arrays of `GiacExpr`, and on `GiacMatrix`.
#
# Ported from Kahli Burke's `ergonomics` branch (src/array_algebra.jl). A `Matrix{GiacExpr}`
# already gets products, `adjoint`, slicing, `tr` and broadcasting from Julia's generic code,
# with Giac doing the scalar algebra; so does a `GiacMatrix`, which is an
# `AbstractMatrix{GiacExpr}`. The methods here fill the gaps where the generic code assumes a
# numeric element type: adding a `UniformScaling` (`A + I`), scaling by an expression, and
# `det`, `inv`, `\`, whose generic LU factorization branches on comparisons of entries. They
# hand off to Giac through `GiacMatrix`.

"""
    Matrix(M::GiacMatrix) -> Matrix{GiacExpr}

The entries of a Giac matrix as a Julia matrix.
"""
Base.Matrix(M::GiacMatrix) = GiacExpr[M[i, j] for i in 1:size(M, 1), j in 1:size(M, 2)]
Base.Matrix{GiacExpr}(M::GiacMatrix) = Matrix(M)

# A Giac matrix is already one.
GiacMatrix(M::GiacMatrix) = M

function _add_scaled_identity(A::AbstractMatrix{GiacExpr}, λ)
    n = LinearAlgebra.checksquare(A)
    B = Matrix{GiacExpr}(A)
    for i in 1:n
        B[i, i] += λ
    end
    return B
end

Base.:+(A::GiacMatrix, J::UniformScaling) = GiacMatrix(_add_scaled_identity(A, J.λ))
Base.:+(J::UniformScaling, A::GiacMatrix) = A + J
Base.:-(A::GiacMatrix, J::UniformScaling) = GiacMatrix(_add_scaled_identity(A, -J.λ))
Base.:-(J::UniformScaling, A::GiacMatrix) = GiacMatrix(_add_scaled_identity(-Matrix(A), J.λ))
Base.:+(A::AbstractMatrix{GiacExpr}, J::UniformScaling) = _add_scaled_identity(A, J.λ)
Base.:+(J::UniformScaling, A::AbstractMatrix{GiacExpr}) = A + J
Base.:-(A::AbstractMatrix{GiacExpr}, J::UniformScaling) = _add_scaled_identity(A, -J.λ)
Base.:-(J::UniformScaling, A::AbstractMatrix{GiacExpr}) = _add_scaled_identity(-A, J.λ)

# Scalars times arrays. `GiacExpr` is not a `Number`, so Julia's own methods don't apply.
Base.:*(x::GiacExpr, A::AbstractArray) = map(a -> x * a, A)
Base.:*(A::AbstractArray, x::GiacExpr) = map(a -> a * x, A)
Base.:/(A::AbstractArray, x::GiacExpr) = map(a -> a / x, A)

"""
    mul!(C, A, B, α::GiacExpr, β::GiacExpr)

`C = α A B + β C` in place, for symbolic scale factors. LinearAlgebra's methods take `Number`s,
which `GiacExpr` is not, and array packages built on the 5-argument form (BlockArrays, through
ArrayLayouts) pass the element type's `one` and `zero`.
"""
function LinearAlgebra.mul!(C::AbstractVecOrMat{GiacExpr}, A::AbstractVecOrMat, B::AbstractVecOrMat,
                            α::GiacExpr, β::GiacExpr)
    AB = A * B
    # β is usually zero, and C may be uninitialized then
    if isequal(β, zero(GiacExpr))
        C .= isequal(α, one(GiacExpr)) ? AB : α .* AB
    else
        C .= α .* AB .+ β .* C
    end
    return C
end

"""
    s * I

A symbolic multiple of the identity, of whatever size the matrix it meets: `s*I - A`.
(`UniformScaling` only holds a `Number`, which `GiacExpr` is not.)
"""
struct SymbolicScaling
    λ::GiacExpr
end

Base.:*(x::GiacExpr, J::UniformScaling) = SymbolicScaling(x * J.λ)
Base.:*(J::UniformScaling, x::GiacExpr) = SymbolicScaling(J.λ * x)
Base.:-(S::SymbolicScaling) = SymbolicScaling(-S.λ)
Base.:+(A::AbstractMatrix, S::SymbolicScaling) = _add_scaled_identity(Matrix{GiacExpr}(A), S.λ)
Base.:+(S::SymbolicScaling, A::AbstractMatrix) = A + S
Base.:-(A::AbstractMatrix, S::SymbolicScaling) = _add_scaled_identity(Matrix{GiacExpr}(A), -S.λ)
Base.:-(S::SymbolicScaling, A::AbstractMatrix) = _add_scaled_identity(-Matrix{GiacExpr}(A), S.λ)
Base.:*(S::SymbolicScaling, A::AbstractArray) = S.λ * A
Base.:*(A::AbstractArray, S::SymbolicScaling) = A * S.λ

# ---------------------------------------------------------------------------------------------
# Vector calculus
# ---------------------------------------------------------------------------------------------

"""
    ∇(f, x::AbstractVector) -> Vector{GiacExpr}

Gradient of the scalar `f` with respect to the variables `x`: `[∂f/∂x₁, …, ∂f/∂xₙ]`.
"""
∇(f, x::AbstractVector) = GiacExpr[Commands.diff(f, xi) for xi in x]

"""
    jacobian(f::AbstractVector, x::AbstractVector) -> Matrix{GiacExpr}

Jacobian `J[i, j] = ∂fᵢ/∂xⱼ`.
"""
jacobian(f::AbstractVector, x::AbstractVector) = GiacExpr[Commands.diff(fi, xj) for fi in f, xj in x]

"""
    hessian(f, x::AbstractVector) -> Matrix{GiacExpr}

Hessian `H[i, j] = ∂²f/∂xᵢ∂xⱼ` of the scalar `f`.
"""
hessian(f, x::AbstractVector) = jacobian(∇(f, x), x)

# ---------------------------------------------------------------------------------------------
# det, inv and \ by Giac
# ---------------------------------------------------------------------------------------------

# A hook for exact linear algebra outside GIAC (Nemo, in a later extension): it returns
# `nothing` while no method is defined, and GIAC computes the result.
function _exact_matrix end
_exact(op::Symbol, args...) = isempty(methods(_exact_matrix)) ? nothing : _exact_matrix(Val(op), args...)

function LinearAlgebra.det(A::AbstractMatrix{GiacExpr})
    d = _exact(:det, A)
    return d === nothing ? det(GiacMatrix(A)) : d
end

# LinearAlgebra's dense `inv(::StridedMatrix)` outranks an `AbstractMatrix{GiacExpr}` method for
# a plain `Matrix`, so both are defined.
function _giac_inv(A)
    B = _exact(:inv, A)
    return B === nothing ? Matrix(inv(GiacMatrix(A))) : B
end
Base.inv(A::AbstractMatrix{GiacExpr}) = _giac_inv(A)
Base.inv(A::StridedMatrix{GiacExpr}) = _giac_inv(A)

"""
    A \\ b

Solve `A x = b` for symbolic `A`, by GIAC's inverse with the entries simplified.
"""
Base.:\(A::AbstractMatrix{GiacExpr}, b::AbstractVecOrMat) = _giac_solve(A, b)
Base.:\(A::StridedMatrix{GiacExpr}, b::AbstractVecOrMat) = _giac_solve(A, b)
function _giac_solve(A, b)
    x = _exact(:solve, A, b)
    return x === nothing ? Commands.simplify.(_giac_inv(A) * b) : x
end

# ---------------------------------------------------------------------------------------------
# Spectra, rank, null space and the matrix exponential, computed by Giac
# ---------------------------------------------------------------------------------------------

"A Giac matrix value (a list of rows) as a `Matrix{GiacExpr}`."
_rows_to_matrix(M::GiacExpr) = permutedims(reduce(hcat, [collect(GiacExpr, row) for row in M]))

"Eigenvalues `D` and eigenvector matrix `V` (as columns) from Giac's Jordan decomposition."
function _jordan(A::AbstractMatrix{GiacExpr})
    LinearAlgebra.checksquare(A)
    PJ = Commands.jordan(GiacMatrix(A))
    V, J = _rows_to_matrix(PJ[1]), _rows_to_matrix(PJ[2])
    n = size(J, 1)
    diagonal = all(iszero(J[i, j]) for i in 1:n, j in 1:n if i != j)
    return V, J, diagonal
end

# The order of eigenvalues that are all numbers: by real part, then imaginary part, as
# LinearAlgebra orders those of a real matrix. Symbolic ones keep GIAC's order.
function _eigen_order(λ::AbstractVector{GiacExpr})
    all(l -> length(free_symbols(l)) == 0, λ) || return collect(eachindex(λ))
    z = [complex(float(to_julia(Commands.evalf(l)))) for l in λ]
    return sortperm(z; by = w -> (real(w), imag(w)))
end

"""
    eigvals(A::AbstractMatrix{GiacExpr}) -> Vector{GiacExpr}

Eigenvalues of a symbolic matrix, with repeats for repeated eigenvalues. Numeric ones are in
increasing order of real part, then imaginary part; symbolic ones keep GIAC's order.
"""
function LinearAlgebra.eigvals(A::AbstractMatrix{GiacExpr})
    λ = _exact(:eigvals, A)            # in order already
    λ === nothing || return λ
    J = _jordan(A)[2]
    return [J[i, i] for i in _eigen_order([J[i, i] for i in axes(J, 1)])]
end

"""
    eigen(A::AbstractMatrix{GiacExpr}) -> Eigen

Eigenvalues and eigenvectors (columns of `vectors`, matching the order of `values`), the values
ordered as [`eigvals`](@ref) orders them. Throws if `A` is not diagonalizable;
`Giac.Commands.jordan` gives the Jordan form instead.
"""
function LinearAlgebra.eigen(A::AbstractMatrix{GiacExpr})
    V, J, diagonal = _jordan(A)
    diagonal || throw(ArgumentError("the matrix is not diagonalizable; use Giac.Commands.jordan for its Jordan form"))
    p = _eigen_order([J[i, i] for i in axes(J, 1)])
    return Eigen([J[i, i] for i in p], V[:, p])
end

LinearAlgebra.eigvecs(A::AbstractMatrix{GiacExpr}) = eigen(A).vectors

function LinearAlgebra.rank(A::AbstractMatrix{GiacExpr})
    r = _exact(:rank, A)
    return r === nothing ? to_julia(Commands.invoke_cmd(:rank, GiacMatrix(A))) : r
end

"""
    nullspace(A::AbstractMatrix{GiacExpr}) -> Matrix{GiacExpr}

A basis of the null space of `A`, as columns (no columns if `A` has full column rank).
"""
function LinearAlgebra.nullspace(A::AbstractMatrix{GiacExpr})
    K = Commands.invoke_cmd(:ker, GiacMatrix(A))
    length(K) == 0 && return Matrix{GiacExpr}(undef, size(A, 2), 0)
    return permutedims(_rows_to_matrix(K))
end

"""
    exp(A::AbstractMatrix{GiacExpr}) -> Matrix{GiacExpr}

The matrix exponential, computed symbolically: `exp(A*t)` is the state-transition matrix of
`ẋ = A x`. Entries come as sums of exponentials (`2e^{-t} - e^{-2t}`); `simplify` would put them
over a common denominator.
"""
Base.exp(A::AbstractMatrix{GiacExpr}) = _giac_exp(A)
_giac_exp(A) = _rows_to_matrix(Commands.invoke_cmd(:exp, GiacMatrix(A)))
Base.exp(A::StridedMatrix{GiacExpr}) = _giac_exp(A)
