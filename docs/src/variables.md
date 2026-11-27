# Symbolic variables

## Simple Variable Creation

Create a symbolic variable with `@giac_var`:

```julia
using Giac

@giac_var a
@giac_var a

a + b

# or simply

@giac_var a b
```

### Arrays of variables

Index a name with ranges to declare an array of variables. The result has
the shape of the ranges, and the names carry subscripts:

```julia
@giac_var z[1:3]          # GiacExpr[z₁, z₂, z₃]
@giac_var m[1:2, 0:1]     # 2×2 Matrix: m₁_₀ m₁_₁; m₂_₀ m₂_₁

k = 4
@giac_var a[1:k]          # ranges may use variables: a₁ … a₄
```

### Matrices of variables

`@giac_matrix` declares matrices of symbolic entries, named like the arrays
above. Sizes may be integers (indices from 1) or ranges, and may use variables.
A structure, a property and assumptions on the entries go in brackets after the
matrix, or after `::`:

```julia
@giac_matrix A[2, 3]                 # A₁_₁ … A₂_₃
@giac_matrix S[2, 2] [symmetric]     # [S₁_₁ S₁_₂; S₁_₂ S₂_₂]
@giac_matrix W[3, 3] [skew]          # [0 W₁_₂ W₁_₃; -W₁_₂ 0 W₂_₃; -W₁_₃ -W₂_₃ 0]
@giac_matrix D[2, 2] [diagonal] U[2, 2] [upper] L[2, 2] [lower]
@giac_matrix V[2, 2] [upper, real]   # assumptions apply to the free entries
@giac_matrix P[2, 2] [posdef]        # symmetric, with a positive diagonal
```

| Specification | Meaning |
|---|---|
| `symmetric` | entry `(j, i)` is entry `(i, j)` |
| `skew` | entry `(j, i)` is minus entry `(i, j)`; zero diagonal |
| `diagonal`, `upper`, `lower` | the other entries are 0 |
| `posdef`, `negdef` | definite: symmetric (or diagonal), diagonal entries positive (negative) |
| `real`, `positive`, `>(0)`, … | assumptions on every free entry, as in `@giac_var` |

Giac's assumptions are on variables, so for `posdef` and `negdef` only the sign of
the diagonal entries reaches Giac. `Giac.matrix_properties(P)` returns the
structure and properties a matrix was declared with.

### Renaming

`v => "name"` binds the Julia variable `v` to a Giac variable with another
name, for instance one that is awkward to type:

```julia
@giac_var v => "𝑣"        # v is the Giac variable 𝑣
@giac_var w(t) => "W"     # w is W(t)
```

## Batch Variable Creation

Create multiple indexed symbolic variables with `@giac_several_vars`. It
names them with plain digits (`a1`, `m12`) and returns a flat tuple; for an
array with subscripted names, use `@giac_var a[1:3]` (see
[Arrays of variables](@ref)).

```julia
using Giac

# 1D vector of variables
@giac_several_vars a 3
# Creates: a1, a2, a3
# Returns: (a1, a2, a3)
a1 + a2 + a3  # Symbolic sum

# 2D matrix of variables
@giac_several_vars m 2 3
# Creates: m11, m12, m13, m21, m22, m23 (row-major order)
# Returns: (m11, m12, m13, m21, m22, m23)

# N-dimensional tensors
@giac_several_vars t 2 2 2
# Creates: t111, t112, t121, t122, t211, t212, t221, t222

# Large dimensions use underscore separators
@giac_several_vars b 2 10
# Creates: b_1_1, b_1_2, ..., b_2_10

# Unicode base names supported
@giac_several_vars α 2
# Creates: α1, α2

# Capture return tuple for iteration
vars = @giac_several_vars c 4
for v in vars
    println(v)
end
```

## Symbolic Comparisons and Inequalities

The comparison operators `<`, `>`, `<=`, `>=` return symbolic inequality expressions
(`GiacExpr`), not booleans. This enables natural syntax for building constraints:

```julia
using Giac

@giac_var x y

# Build symbolic inequalities
x > 0        # Returns a GiacExpr representing x>0
x < y        # Returns a GiacExpr representing x<y
x >= 1//2    # Works with Rational
x <= π       # Works with Irrational
```

Combine inequalities with `&` (and) and `|` (or):

```julia
(x > 0) & (x < 10)    # GIAC "and" expression
(x < -1) | (x > 1)    # GIAC "or" expression
```

## Assumptions on Variables

### Assumptions in `@giac_var`

Declare a variable with assumptions by annotating it. Later computations take
them into account:

```julia
using Giac
using Giac.Commands: about, sqrt, sign

@giac_var x::positive
sqrt(x^2)                  # x (abs(x) without the assumption)
sign(x)                    # 1

@giac_var n::(integer, >=(0))
about(n)                   # assume[integer,[line[0,+infinity]],[]]

c = 2
@giac_var y::(<(c))        # bounds are evaluated: y < 2
@giac_var a[1:3]::real     # every element of the array is real
@giac_var (r => "ρ")::positive
```

| Kind | Values |
|---|---|
| Domain | `real`, `complex`, `rational`, `integer` (also `Real`, `Complex`, `Rational`, `Integer`) |
| Range | `positive`, `negative`, `nonnegative`, `nonpositive`, `finite` |
| Comparison | `<(b)`, `<=(b)`, `>=(b)`, `>(b)`, with `b` any number, Julia variable or `GiacExpr` |
| Function | `[domain = v -> v > 0]`: called with the variable, returns a Giac condition |

Several assumptions go in a tuple, `x::(integer, positive)`. The
Symbolics.jl-style metadata syntax also works: `x [positive, real]`,
`x [domain = Real]`. An unknown assumption is an error when the code is
parsed, and functions such as `u(t)` take no assumptions.

Declaring a variable starts it afresh: a value bound with `:=` and earlier
assumptions are removed, so `@giac_var x` after `@giac_var x::positive` gives
back a plain `x`. Like `assume`, assumptions live in Giac's global state for
the rest of the session.

### `assume` and `additionally`

Use `assume` and `additionally` to declare constraints on symbolic variables
that already exist. Subsequent computations will respect these assumptions:

```julia
using Giac
using Giac.Commands: assume, about, sign, purge, additionally, sqrt

@giac_var x

# Declare x as positive
assume(x > 0)
sign(x)      # Returns 1
sqrt(x^2)    # Returns x (simplified thanks to assumption)

# Interval constraint using &
assume((x > 0) & (x < 10))
about(x)     # Shows interval [0, 10]

# Or use assume + additionally
assume(x > -1)
additionally(x < 1)
about(x)     # Shows interval [-1, 1]

# Clear assumptions
purge(x)
```

!!! note
    Julia's chained comparison syntax `0 < x < 10` does not work because Julia
    desugars it using `&&` (which cannot be overloaded). Use `(x > 0) & (x < 10)`
    or `assume` + `additionally` instead.

!!! warning
    When a variable already has an assumption, GIAC evaluates comparisons involving
    that variable to `true` or `false` instead of keeping them symbolic. This means
    calling `assume` a second time without `purge` first will fail:

    ```julia
    assume(x > 0)
    additionally(x < 10)
    # x > 0 now evaluates to "true" (GIAC knows x is positive)
    assume(x > 0)  # ERROR: assume(true) is invalid

    # Fix: always purge before re-assuming
    purge(x)
    assume(x > 0)  # Works
    ```
### Assumptions for one block: `assuming`

GIAC's assumptions are global: `assume(x > 0)` holds for everything evaluated
afterwards, until `purge(x)`. `assuming` puts conditions in force for one block
and undoes them afterwards, even when the block throws:

```julia
using Giac.Commands: simplify, about
@giac_var k n

assuming(k > 0) do
    simplify(sqrt(k^2))        # k
end
simplify(sqrt(k^2))            # abs(k): nothing is assumed any more

assuming(k > 0, k < 1) do      # conditions on one variable combine
    about(k)                   # the interval ]0, 1[
end
assuming(n => :integer) do     # a domain: :real, :integer, :complex, :rational
    # ...
end
```

The conditions add to what a variable was declared with (`@giac_var k::real`),
and when the block ends every variable named in them gets back exactly the
state GIAC held for it before. A condition GIAC already decides from those
assumptions (`k > 0` for a positive `k`) is skipped, and one it finds false is
an error. The GIAC lock is held for the whole block, so other tasks wait and
none sees the temporary assumptions.

## Settings that change results

Some session settings change what a computation means: with `complex_mode` on,
`simplify(sqrt(x^2))` gives `x`, which is wrong at `x = -2`. `giac_settings()`
reads them as one record, to report next to a result, and `with_settings` sets
some of them for one block, then puts every setting back:

```julia
giac_settings()
# (complex_mode = false, approx_mode = false, angle_radian = true,
#  complex_variables = false, epsilon = 1.0e-12, digits = 12)

@giac_var x
with_settings(complex_mode = false) do
    Giac.Commands.simplify(sqrt(x^2))      # abs(x), whatever the session's setting
end
with_settings(digits = 30) do
    Giac.Commands.evalf(pi)
end
```

`assuming` also puts the settings back when its block ends.
