# Linear Algebra

Giac.jl provides comprehensive symbolic linear algebra capabilities including matrix operations, determinants, eigenvalues, and linear system solving.

## Setup

```julia
using Giac, LinearAlgebra
using Giac.Commands: eigenvalues, linsolve

@giac_var a b c d x y
```

## Matrix Creation

### Numeric Matrices

Create matrices from Julia arrays:

```julia
A = GiacMatrix([1 2; 3 4])
# 2×2 GiacMatrix:
#  1  2
#  3  4
```

### Symbolic Matrices

Create matrices with symbolic entries:

```julia
@giac_var a b c d
B = GiacMatrix([[a, b],
                [c, d]])
# 2×2 GiacMatrix:
#  a  b
#  c  d
```

### Symbol Constructor

Create large symbolic matrices using the symbol constructor:

```julia
@giac_several_vars m 2 2
M = GiacMatrix([[m11, m12],
                [m21, m22]])
det(M)  # m11*m22-m12*m21

# Or use the compact constructor:
M = GiacMatrix(:m, 3, 3)
# 3×3 GiacMatrix with entries m11, m12, ...
```

For very large matrices:

```julia
M = GiacMatrix(:m, 100, 100)
# 100×100 GiacMatrix:
#   m_1_1    m_1_2    m_1_3    ...    m_1_100
#   m_2_1    m_2_2    m_2_3    ...    m_2_100
#      ⋮        ⋮        ⋮     ⋱          ⋮
# m_100_1  m_100_2  m_100_3   ...  m_100_100
```

### Custom Index Ranges

Create matrices with non-1-based indexing using UnitRange or StepRange arguments:

```julia
# 0-based indexing (useful for physics, quantum mechanics)
M = GiacMatrix(:ψ, 0:2, 0:2)
# 3×3 GiacMatrix with entries ψ00, ψ01, ψ02, ψ10, ψ11, ...

# Negative indices (useful for angular momentum states)
J = GiacMatrix(:J, -1:1)
# 3×1 column vector with entries J_m1, J_0, J_1 (m = minus)

# Custom ranges
A = GiacMatrix(:A, 5:7, 1:3)
# 3×3 GiacMatrix with entries A51, A52, A53, A61, ...

# StepRange for even indices
E = GiacMatrix(:E, 0:2:6)
# 4×1 column vector with entries E0, E2, E4, E6

# Mixed integer and range arguments
M = GiacMatrix(:M, 3, 0:2)
# 3×3 matrix: rows use 1:3, columns use 0:2
# Entries: M10, M11, M12, M20, M21, M22, M30, M31, M32
```

The same range syntax works with `@giac_several_vars`:

```julia
@giac_several_vars ψ 0:2
# Creates: ψ0, ψ1, ψ2

@giac_several_vars T 0:1 0:2
# Creates: T00, T01, T02, T10, T11, T12

@giac_several_vars c -1:1
# Creates: c_m1, c_0, c_1 (m = minus for negative indices)
```

**Naming Convention:**
- Indices 0-9: concatenated directly (e.g., `m12`, `ψ00`)
- Indices > 9: underscore separators (e.g., `m_1_10`)
- Negative indices: `m` prefix for minus (e.g., `-1` → `m1`, so `c_m1` for index -1)

## Iteration and Linear Indexing

`GiacMatrix` is an `AbstractMatrix{GiacExpr}`, so it supports the standard Julia
iteration, indexing and slicing protocols. Iteration order is **column-major**,
matching Julia's `Matrix`.

### `length` and basic iteration

```julia
@giac_var x y
M = GiacMatrix([x   y   x+y;
                2*x 2*y x*y])     # 2×3

length(M)            # 6  (= rows * cols)

for e in M
    println(e)       # x, 2*x, y, 2*y, x+y, x*y  (column-major)
end

collect(M)           # 2×3 Matrix{GiacExpr}: collect keeps the shape
```

### Linear indexing `M[i]` and Cartesian-index access

```julia
@giac_var x y
M = GiacMatrix([x   y   x+y;
                2*x 2*y x*y])

M[1]                  # x       (= M[1, 1])
M[3]                  # y       (= M[1, 2])
M[5]                  # x + y   (= M[1, 3])

M[CartesianIndex(2, 3)]   # x*y  (same as M[2, 3])
```

### `LinearIndices(M)` and `CartesianIndices(M)`

```julia
LI = LinearIndices(M)
LI[1, 1], LI[2, 1], LI[1, 2]      # 1, 2, 3       (column-major)

CI = CartesianIndices(M)
CI[1], CI[3], CI[5]
# CartesianIndex(1,1), CartesianIndex(1,2), CartesianIndex(1,3)
```

These are convenient for routines that take a `GiacMatrix` and want to walk
its entries with a linear counter, or convert between the two index forms:

```julia
LI = LinearIndices(M)
for i in 1:M.rows, j in 1:M.cols
    @assert M[LI[i, j]] === M[i, j] || string(M[LI[i, j]]) == string(M[i, j])
end
```

## Julia arrays of expressions

Because `GiacMatrix` is an `AbstractMatrix{GiacExpr}`, a Giac matrix and an
ordinary `Matrix{GiacExpr}` work with the same Julia code: slicing, `A'`,
broadcasting, block concatenation and `LinearAlgebra`. Giac does the scalar
algebra, and the operations Julia's generic code cannot do on symbolic entries
(determinant, inverse, solves, spectra) are handed to Giac.

```julia
@giac_var a11 a12 a21 a22 x1 x2 s t
A = [a11 a12; a21 a22]           # a Matrix{GiacExpr}
x = [x1, x2]

M = GiacMatrix(A)
M[:, 1]                          # [a11, a21]
Matrix(M)                        # back to a Matrix{GiacExpr}

A + I                            # [a11+1 a12; a21 a22+1]
s * I - A                        # a symbolic multiple of the identity
[A I; I A']                      # block matrices; `true` and `false` are 1 and 0
t * x                            # [t*x1, t*x2]

det(A)                           # a11*a22-a12*a21
inv(A)                           # a Matrix{GiacExpr}
A \ x                            # solves A y = x

E = GiacExpr[0 1; -2 -3]
eigvals(E)                       # [-2, -1]: numbers by real part, then imaginary part
eigen(E)                         # values and eigenvectors (throws if not diagonalizable)
rank(E), nullspace(GiacExpr[1 2; 2 4])
exp(E * t)                       # the state-transition matrix of ẋ = E x
```

A Giac matrix stays one under scaling by a number or an expression, division,
negation, `± I` and `kron`, and generated commands accept a `Matrix{GiacExpr}`
as they accept a `GiacMatrix`:

```julia
using Giac.Commands: eigenvalues
@giac_var θ
σz, σx = GiacMatrix([1 0; 0 -1]), GiacMatrix([0 1; 1 0])
σθ = cos(θ) * σz + sin(θ) * σx   # a GiacMatrix
σz / 2                           # exact: [1/2 0; 0 -1/2]
eigenvalues(Matrix(σθ))          # same as eigenvalues(σθ)
```

### Matrix equations

`A ~ B` between arrays of the same shape is the array of equations between their
entries. The right side may also be `I`, `-I`, a symbolic multiple `s*I`, or one
value for every entry. `solve(eqs, X)` solves for the free entries of a matrix
unknown and returns `X` with its entries replaced; repeated equations, from a
symmetric unknown say, count once.

```julia
using Giac.Commands: solve
@giac_var a11 a12 a21 a22 p11 p12 p22
A = [a11 a12; a21 a22]
P = [p11 p12; p12 p22]           # a symmetric unknown

A ~ I                            # [a11=1 a12=0; a21=0 a22=1]
P★ = solve(P*A + A'*P ~ -I, P)   # the Lyapunov equation, solved for P
```

`solve` throws an `ArgumentError` if the equations have no solution, or more
than one.

### Gradient, Jacobian and Hessian

```julia
@giac_var w1 w2 k
w = [w1, w2]
f = w1^2 * w2 + k * w2
∇(f, w)                          # [2*w1*w2, w1^2+k]
hessian(f, w)                    # [2*w2 2*w1; 2*w1 0]
jacobian([w1 * w2, w1 + w2], w)  # [w2 w1; 1 1]
```

## Determinant

Compute the determinant using `det`:

```julia
A = GiacMatrix([1 2; 3 4])
det(A)
# Output: -2

# Symbolic determinant
@giac_var a b c d
B = GiacMatrix([[a, b], [c, d]])
det(B)
# Output: a*d-b*c
```

## Inverse

Compute the matrix inverse using `inv`:

```julia
A = GiacMatrix([1 2; 3 4])
inv(A)
# Returns the inverse matrix
```

For singular matrices, GIAC will return an error.

## Trace

Compute the trace (sum of diagonal elements) using `tr`:

```julia
A = GiacMatrix([1 2; 3 4])
tr(A)
# Output: 5
```

## Transpose

Compute the transpose using `transpose`:

```julia
A = GiacMatrix([1 2; 3 4])
transpose(A)
# 2×2 GiacMatrix:
#  1  3
#  2  4
```

## Eigenvalues and Eigenvectors

### Eigenvalues

Compute eigenvalues using the `eigenvalues` command from `Giac.Commands`:

```julia
using Giac.Commands: eigenvalues

A = GiacMatrix([2 1; 1 2])
# Convert GiacMatrix to GiacExpr via ptr for eigenvalues command
eigenvalues(GiacExpr(A.ptr))
# Output: 3,1
```

### Characteristic Polynomial

The characteristic polynomial can be computed for eigenvalue analysis.

## Linear System Solving

### Using linsolve

Solve systems of linear equations using `linsolve`:

```julia
using Giac.Commands: linsolve

@giac_var x y

# System: x + y = 3, x - y = 1
linsolve([x + y ~ 3, x - y ~ 1], [x, y])
# Output: [2, 1]
```

### Using solve

The general `solve` command also works for linear systems:

```julia
using Giac.Commands: solve

solve([x + y ~ 3, x - y ~ 1], [x, y])
# Returns the solution
```

`Giac.Commands.solve` is the same generic function as
[`CommonSolve.solve`](https://github.com/SciML/CommonSolve.jl), so it shares
the "solve" verb with `DifferentialEquations.jl`, `NLsolve.jl`, `Symbolics.jl`,
etc. Dispatch is by argument type, so there is no name conflict when both
packages are loaded — `solve(eq::GiacExpr, var)` routes to Giac,
`solve(prob::ODEProblem, …)` routes to DifferentialEquations, and so on.

```julia
using Giac.Commands: solve   # this is the same function as CommonSolve.solve

solve(x^2 - 1 ~ 0, x)   # → list[-1, 1]
# The `~` operator builds a symbolic equation; Giac dispatches the
# CommonSolve.solve verb to its CAS solver.
```

Either side of the equation works:

```julia
solve(x^2 ~ 1, x)        # → list[-1, 1]
solve(x^2 - 1, x)        # → list[-1, 1]   (Giac infers `= 0`)
```

!!! note "Why `solve` only, and not `init` / `solve!`"

    `CommonSolve` defines three verbs — `init`, `solve`, and `solve!` — to
    support the iterative-solver protocol used by `DifferentialEquations.jl`
    and friends (`init(prob, …)` builds an integrator, `solve!` advances it,
    `solve` is a one-shot wrapper that does both). Giac is a one-shot
    symbolic solver — there is no integrator state to advance — so only
    `solve` has a natural meaning here. `Giac` therefore extends
    `CommonSolve.solve` and leaves `init` and `solve!` untouched, so
    packages that *do* implement the iterative protocol can extend them
    without any conflict.

    Giac also has its own ODE solver, `Giac.Commands.desolve` (symbolic) and
    `Giac.Commands.odesolve` (numerical) — see
    [Differential Equations](differential_equations.md). Those are
    intentionally separate verbs (not aliased to `solve`) because their
    signatures don't fit the algebraic `solve(eq, var)` shape.

## Matrix Rank

Compute the rank of a matrix using `invoke_cmd(:rank, ...)`:

```julia
A = GiacMatrix([1 2 3; 4 5 6; 7 8 9])
# Use invoke_cmd because rank conflicts with LinearAlgebra.rank
# Convert GiacMatrix to GiacExpr via ptr
invoke_cmd(:rank, GiacExpr(A.ptr))
# Output: 2 (linearly dependent rows)
```

## Matrix Operations

### Addition and Subtraction

```julia
A = GiacMatrix([1 2; 3 4])
B = GiacMatrix([5 6; 7 8])

A + B
# 2×2 GiacMatrix:
#  6   8
# 10  12

A - B
# 2×2 GiacMatrix:
# -4  -4
# -4  -4
```

### Matrix Multiplication

```julia
A = GiacMatrix([1 2; 3 4])
B = GiacMatrix([5 6; 7 8])

A * B
# 2×2 GiacMatrix:
# 19  22
# 43  50
```

### Scalar Multiplication

```julia
A = GiacMatrix([1 2; 3 4])

2 * A
# 2×2 GiacMatrix:
# 2  4
# 6  8
```

### Matrix Powers

```julia
A = GiacMatrix([1 2; 3 4])

A^2
# Computes A * A
```

## Table of Functions

| Function | Description |
|----------|-------------|
| `GiacMatrix(array)` | Create symbolic matrix from array |
| `GiacMatrix(:sym, m, n)` | Create m×n symbolic matrix (1-based) |
| `GiacMatrix(:sym, a:b, c:d)` | Create matrix with custom index ranges |
| `GiacMatrix(:sym, m, a:b)` | Mixed integer and range arguments |
| `det(M)` | Determinant |
| `inv(M)` | Inverse |
| `tr(M)` | Trace |
| `transpose(M)` | Transpose |
| `eigenvalues(GiacExpr(M.ptr))` | Eigenvalues |
| `linsolve(eqs, vars)` | Solve linear system |
| `invoke_cmd(:rank, GiacExpr(M.ptr))` | Matrix rank |
| `M[:, j]`, `M[i, :]`, `Matrix(M)` | Slices and the Julia matrix of entries |
| `A ± I`, `s * I - A` | Add a (symbolic) multiple of the identity |
| `det(A)`, `inv(A)`, `A \ b` | On any `AbstractMatrix{GiacExpr}`, by Giac |
| `eigvals(A)`, `eigen(A)`, `eigvecs(A)` | Spectrum, by Giac's Jordan form |
| `rank(A)`, `nullspace(A)`, `exp(A)` | Rank, null-space basis, matrix exponential |
| `∇(f, x)`, `jacobian(f, x)`, `hessian(f, x)` | Gradient, Jacobian, Hessian |

## Notes

- All matrix operations work symbolically
- For numerical evaluation, use `to_julia` to convert results
- Large symbolic matrices can be created efficiently using the symbol constructor
- The `~` operator creates equations for use with `linsolve` and `solve`
