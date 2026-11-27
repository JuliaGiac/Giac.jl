# Core API

The main Giac module provides core types and functions for symbolic computation.

```@docs
Giac
```

## Types

```@docs
GiacExpr
GiacContext
GiacMatrix
GiacError
HelpResult
GiacCommand
GiacInput
```

## Expression Evaluation

```@docs
giac_eval
giac_version
```

## Numbers and approximate equality

`GiacExpr(x)` builds an expression from any Julia number, like
`convert(GiacExpr, x)`: `GiacExpr(3//4)` is the exact `3/4`, and
`GiacExpr.(M)` converts a numeric matrix entry by entry.

```@docs
Base.isapprox(::GiacExpr, ::GiacExpr)
```

```julia
@giac_var x y
sqrt(GiacExpr(2)) ≈ 1.4142135623730951   # true: compared by numeric value
1.0000000001x + y ≈ x + y                # true: coefficients compared
sin(x)^2 + cos(x)^2 ≈ 1                  # true: the expressions are equal
isapprox(GiacExpr(π), 355//113; rtol = 1e-6)  # true
```

## Symbolic Variables

```@docs
@giac_var
@giac_several_vars
@giac_matrix
Giac.matrix_properties
```

### Assumptions for one block and settings

```@docs
assuming
with_settings
giac_settings
assumptions
Giac.Assumptions
is_free_identifier
fresh_identifier
with_fresh_identifiers
```

### Function Syntax for @giac_var

The `@giac_var` macro supports function notation for defining symbolic functions that depend on other variables. This is useful for differential equations and calculus with unknown functions.

**Single-variable functions:**
```julia
@giac_var u(t)        # u is a GiacExpr representing "u(t)"
@giac_var t           # t is the independent variable
diff(u, t)            # Symbolic derivative of u with respect to t
```

**Multi-variable functions:**
```julia
@giac_var f(x, y)     # f represents "f(x,y)"
@giac_var x y
diff(f, x)            # Partial derivative ∂f/∂x
diff(f, y)            # Partial derivative ∂f/∂y
```

**Mixed declarations:**
```julia
@giac_var t x y u(t) f(x, y)
# Creates: t, x, y as simple variables
#          u as "u(t)", f as "f(x,y)"
```

**Common use case - ODEs:**
```julia
@giac_var t u(t)
# Express ODE: u''(t) + u(t) = 0
```

**Common use case - PDEs:**
```julia
@giac_var x y u(x, y)
# Laplacian: ∂²u/∂x² + ∂²u/∂y²
laplacian = diff(diff(u, x), x) + diff(diff(u, y), y)
```

### Callable GiacExpr (Function Evaluation)

GiacExpr objects are callable, allowing natural function evaluation syntax like `u(0)`. This is essential for specifying ODE initial conditions.

**Basic function evaluation:**
```julia
@giac_var u(t)
u(0)           # Returns GiacExpr: "u(0)"
u(1)           # Returns GiacExpr: "u(1)"
```

**ODE initial conditions:**
```julia
using Giac.Commands: diff, desolve
@giac_var t u(t) tau U0

# ODE: τu' + u = U₀ with u(0) = 1
ode = tau * diff(u, t) + u ~ U0
initial = u(0) ~ 1
desolve([ode, initial], u)
```

**Derivative initial conditions (using D operator):**
```julia
using Giac.Commands: desolve
@giac_var t u(t)

# First derivative at t=0: u'(0) = 1
Differential(t)(u)(0) ~ 1

# Second derivative at t=0: u''(0) = 0
Differential(t, 2)(u)(0) ~ 0

# Full example: solve u'' + u = 0 with u(0)=1, u'(0)=0
ode = Differential(t, 2)(u) + u ~ 0
u0 = u(0) ~ 1
du0 = Differential(t)(u)(0) ~ 0
desolve([ode, u0, du0], t, :u)  # Returns: cos(t)
```

### D Operator (Derivative Operator)

The `D` operator follows SciML/ModelingToolkit conventions for expressing derivatives:

```julia
@giac_var t u(t)

# Create derivative expressions
Differential(t)(u)        # First derivative u'
Differential(t, 2)(u)     # Second derivative u'' (chained)
Differential(t, 2)(u)     # Second derivative u'' (direct)
Differential(t, 3)(u)     # Third derivative u'''

# Use in ODE equations
ode = Differential(t, 2)(u) + u ~ 0    # u'' + u = 0

# Use in initial conditions (produces prime notation for GIAC)
Differential(t)(u)(0) ~ 1              # u'(0) = 1
Differential(t, 2)(u)(0) ~ 0           # u''(0) = 0
```

**Complete ODE examples:**

```julia
using Giac
using Giac.Commands: desolve

# 2nd order: u'' + u = 0, u(0)=1, u'(0)=0
@giac_var t u(t)
result = desolve([Differential(t, 2)(u) + u ~ 0, u(0) ~ 1, Differential(t)(u)(0) ~ 0], t, :u)
# Returns: cos(t)

# 3rd order: y''' - y = 0, y(0)=1, y'(0)=1, y''(0)=1
@giac_var t y(t)
result = desolve([Differential(t, 3)(y) - y ~ 0, y(0) ~ 1, Differential(t)(y)(0) ~ 1, Differential(t, 2)(y)(0) ~ 1], t, :y)
# Returns: exp(t)
```

!!! note "desolve function argument"
    When calling `desolve`, pass the function name as a Symbol (`:u`, `:y`) rather than
    the function expression (`u`, `y`), since GIAC expects just the name, not `u(t)`.

**Multi-variable function evaluation:**
```julia
@giac_var f(x, y) a b
f(0, 0)        # Returns "f(0,0)"
f(a, b)        # Returns "f(a,b)"
f(1, 2)        # Returns "f(1,2)"
```

## Exact Numbers

A decimal literal is a binary floating-point number before Giac sees it:
`0.1` is the double nearest ``1/10``, and `0.1 + 0.2` is `0.30000000000000004`
in Julia. Giac keeps such a number as a float, and its doubles carry fewer
mantissa bits than Julia's `Float64` (some bits hold the type tag), so what
Giac computes from them is good to about 12 significant digits:
`sqrt(convert(GiacExpr, 2.0))` differs from Julia's `sqrt(2.0)` by about
`3e-12`. The same goes for `2π` (a `Float64` product, computed before any Giac
code runs) and for `sqrt(2)` or `1/2` of integer literals.

`@exact` rewrites the numbers of the code it is given into exact Giac numbers
before Julia computes with them. It is the recommended way to write decimals
in symbolic code:

```julia
using Giac
using Giac.Commands: factor, solve
@giac_var x

0.1 + 0.2                        # 0.30000000000000004 (a Julia Float64)
@exact 0.1 + 0.2                 # 3/10

2π * x                           # 6.283185307179586*x
@exact 2π * x                    # 2*pi*x

solve(x^2 - 0.5, x)              # list[-0.707106781187,0.707106781187]
@exact solve(x^2 - 0.5, x)       # list[-1/2*sqrt(2),1/2*sqrt(2)]

factor(x^2 + 0.1x)               # x*(x+0.1)
@exact factor(x^2 + 0.1x)        # x*(10*x+1)/10

@exact exp(0.5) + sqrt(2) / 2    # exp(1/2)+sqrt(2)/2
```

```@docs
@exact
```

What is rewritten, each into a `GiacExpr`:

| Written | Under `@exact` | Without it |
|---------|----------------|------------|
| `0.1`, `2.5e-3`, `1.5f0` | `1/10`, `1/400`, `3/2`: the shortest decimal form, the digits Julia prints | the binary double |
| `big(0.1)`, `big"0.1"` | `1/10` | a `BigFloat` |
| `π`, `pi`, `ℯ` | Giac's `pi` and `exp(1)` | an `Irrational`, a float once multiplied |
| `sqrt(2)`, `cbrt(2)` | `sqrt(2)`, `2^(1/3)` | `1.4142135623730951`, `1.2599210498948732` |
| `2^(1/3)`, `2^-1` | `2^(1/3)`, `1/2` | `1.2599210498948732`, `0.5` |
| `1/2` | `1/2` | `0.5` |

What is left as written:

- **Integers** and integer arithmetic: `@exact 2 * 3` is the Julia `6`, and an
  integer literal too large for `Int` stays an `Int128` or a `BigInt`, which
  Giac receives exactly. Julia's integer overflow still applies, so write
  `big(10)^20` rather than `10^20`.
- **Floats that are not literals**: with `y = 0.1`, `@exact y * x` keeps the
  float held by `y`; only the digits written inside the macro call are read.
  For a float computed elsewhere, Giac's `exact` command
  (`Giac.Commands.exact(convert(GiacExpr, y))`) gives a nearby fraction.
- **Qualified constants** (`Base.pi`), **quoted code** (`:(0.1)`), and the
  code of **other macros** inside the expression: put `@exact` inside the
  other macro call rather than around it. A nested `@exact` expands on its own.

A name assigned by the macro's own assignments (in its block, not in a loop
or function inside it) is bound to the Giac number, so what is computed from
it later is exact as well:

```julia
@exact begin
    h = 0.1                      # 1/10, a GiacExpr
    three = 3                    # a Giac 3: sqrt(three) is sqrt(3)
end
```

Every literal of the expression is rewritten, so keep numeric code such as
ranges, tolerances or plotting outside `@exact`.

!!! note "IntervalArithmetic.jl"
    IntervalArithmetic.jl also exports a macro named `@exact`, which keeps
    the binary value of each float. With both packages loaded, write
    `Giac.@exact`.

## Calculus Operations

Calculus functions are available via `Giac.Commands` or `invoke_cmd`:

```julia
using Giac
using Giac.Commands: diff, integrate, limit, series

# Or use invoke_cmd
invoke_cmd(:diff, expr, x)
invoke_cmd(:integrate, expr, x)
invoke_cmd(:limit, expr, x, point)
invoke_cmd(:series, expr, x, point, order)
```

## Algebraic Operations

Algebra functions are available via `Giac.Commands` or `invoke_cmd`:

```julia
using Giac
using Giac.Commands: factor, expand, simplify, solve, gcd

# Or use invoke_cmd
invoke_cmd(:factor, expr)
invoke_cmd(:expand, expr)
invoke_cmd(:simplify, expr)
invoke_cmd(:solve, expr, x)
invoke_cmd(:gcd, a, b)
```

## Taylor Polynomials and Collecting Terms

```@docs
taylor
collect_terms
Giac.coefficients
```

A function of Giac that has the name of a GIAC command (`taylor`) is not exported
from `Giac.Commands` as well, so `using Giac, Giac.Commands` keeps the name
unambiguous; the GIAC command is `Giac.Commands.taylor`.

## Vector Input Support

GIAC commands accept Julia vectors directly, enabling natural syntax for systems of equations and matrix operations:

```julia
using Giac
using Giac.Commands: solve, det_minor, inverse
@giac_var x y z

# Solve systems of equations with vector syntax
solve([x + y ~ 1, x - y ~ 0], [x, y])  # Returns [[1/2, 1/2]]

# Three-variable system
solve([x + y + z ~ 6, x - y ~ 0, y + z ~ 4], [x, y, z])

# Matrix operations with nested vectors
det_minor([[1, 2], [3, 4]])  # Returns -2
inverse([[1, 2], [3, 4]])    # Returns inverse matrix
```

See [`GiacInput`](@ref) for the full list of supported input types.

## GiacMatrix Command Support

`GiacMatrix` objects can be passed directly to GIAC commands, both via `invoke_cmd` and generated command functions:

```julia
using Giac
using Giac.Commands: eigenvals, trace

M = GiacMatrix([[1, 2], [3, 4]])

# Direct command calls
eigenvals(M)              # Returns eigenvalues
trace(M)                  # Returns 5

# Via invoke_cmd (works for all commands including Base-conflicting ones)
invoke_cmd(:det, M)       # Returns -2
invoke_cmd(:transpose, M) # Returns transposed matrix
invoke_cmd(:eigenvals, M) # Returns eigenvalues
```

Generated commands also accept a Julia `Matrix{GiacExpr}`, which they pass to
GIAC as a `GiacMatrix`.

## Arrays of expressions

`GiacMatrix` is an `AbstractMatrix{GiacExpr}`. These methods work on it and on
any Julia array of `GiacExpr` (see [Linear Algebra](../mathematics/linear_algebra.md)).

```@docs
Base.Matrix(::GiacMatrix)
Giac.SymbolicScaling
Giac.LinearAlgebra.mul!(::AbstractVecOrMat{GiacExpr}, ::AbstractVecOrMat, ::AbstractVecOrMat, ::GiacExpr, ::GiacExpr)
Giac.LinearAlgebra.eigvals(::AbstractMatrix{GiacExpr})
Giac.LinearAlgebra.eigen(::AbstractMatrix{GiacExpr})
Giac.LinearAlgebra.nullspace(::AbstractMatrix{GiacExpr})
Base.exp(::AbstractMatrix{GiacExpr})
Base.kron(::GiacMatrix, ::GiacMatrix)
∇
jacobian
hessian
```

## Equations

```@docs
lhs
rhs
isolate
Base.:~(::AbstractArray{GiacExpr}, ::AbstractArray)
Giac.Commands.solve(::AbstractArray{GiacExpr}, ::AbstractMatrix{GiacExpr})
```

## Command Discovery

```@docs
list_commands
help_count
search_commands
commands_in_category
command_info
list_categories
giac_help
```

!!! note "Getting Help for Commands"
    Use Julia's native help system after importing commands:
    ```julia
    using Giac.Commands: factor
    ?factor  # Shows GIAC documentation
    ```

## Command Suggestions

```@docs
suggest_commands
set_suggestion_count
get_suggestion_count
search_commands_by_description
```

## Namespace Management

```@docs
JULIA_CONFLICTS
exportable_commands
is_valid_command
conflict_reason
available_commands
reset_conflict_warnings!
```

## Substitution

See [Variable Substitution](../substitute.md) for the `substitute` function documentation.

## Type Introspection

Functions for querying the type of GIAC expressions:

```@docs
Giac.giac_type
Giac.subtype
Giac.is_integer
Giac.is_numeric
Giac.is_vector
Giac.is_symbolic
Giac.is_identifier
Giac.is_fraction
Giac.is_complex
Giac.is_string
Giac.is_boolean
Giac.is_constant
Giac.hasmatch
Giac.free_symbols
Giac.unwrap_const
Giac.Constants.is_giac_constant
```

### Type Enum (GenTypes)

GIAC expression types are available via the `Giac.GenTypes` module with the `T` enum:

```julia
using Giac.GenTypes: T, INT, DOUBLE, VECT, SYMB

giac_type(expr) == INT   # Check if expression is an integer
giac_type(expr) == VECT  # Check if expression is a vector
```

| Enum Value | Int | Description |
|------------|-----|-------------|
| `INT` | 0 | Machine integer (Int64) |
| `DOUBLE` | 1 | Double-precision float (Float64) |
| `ZINT` | 2 | Arbitrary-precision integer (BigInt) |
| `REAL` | 3 | Extended precision real |
| `CPLX` | 4 | Complex number |
| `POLY` | 5 | Polynomial |
| `IDNT` | 6 | Identifier/variable |
| `VECT` | 7 | Vector/list/sequence |
| `SYMB` | 8 | Symbolic expression |
| `SPOL1` | 9 | Sparse polynomial |
| `FRAC` | 10 | Rational fraction |
| `EXT` | 11 | Algebraic extension |
| `STRNG` | 12 | String value |
| `FUNC` | 13 | Function reference |
| `ROOT` | 14 | Polynomial root |
| `MOD` | 15 | Modular arithmetic |
| `USER` | 16 | User-defined type |
| `MAP` | 17 | Map/dictionary |
| `EQW` | 18 | Equation writer data |
| `GROB` | 19 | Graphic object |
| `POINTER` | 20 | Raw pointer |
| `FLOAT` | 21 | Float value |

```@docs
Giac.GenTypes
Giac.GenTypes.T
```

## Component Access

Functions for accessing components of compound types:

```@docs
Giac.numer
Giac.denom
Giac.real_part
Giac.imag_part
Giac.symb_funcname
Giac.symb_argument
```

### Julia Standard Interface

`Base.numerator` and `Base.denominator` are also extended for `GiacExpr`, delegating to GIAC's `numer`/`denom` commands. These handle both numeric and symbolic fractions:

```julia
numerator(giac_eval("25/15"))          # 5
denominator(giac_eval("25/15"))        # 3

@giac_var x
numerator((x^3 - 1) / (x^2 - 1))     # x^2+x+1
denominator((x^3 - 1) / (x^2 - 1))   # x+1
```

## Conversion Functions

```@docs
Giac.to_julia
Giac.to_giac
Giac.to_symbolics
Giac.to_symbolicutils
Giac.giac_source
```

### How numbers are read

`to_julia`, `float`, `Float64(g)`, `convert(Float64, g)`, `Complex(g)` and
`Rational(g)` read a GIAC number as follows.

**Doubles (`DOUBLE`) are read from the decimal GIAC prints for them**, at
`Digits` significant digits (12 by default). This applies to the parts of a
complex double and to the elements of a vector or matrix too:

```julia
to_julia(giac_eval("0.1+0.2"))               # 0.3
to_julia(giac_eval("sqrt(2.0)"))             # 1.41421356237
to_julia(giac_eval("sqrt(2.0) + sqrt(3.0)*i"))  # 1.41421356237 + 1.73205080757im
```

GIAC's doubles carry fewer mantissa bits than Julia's `Float64`: GIAC keeps
its type tag in the low byte of the 64-bit word, which leaves 45 bits of
mantissa instead of 53. The bits GIAC stores are therefore not a better
reading than the printed decimal (for `0.1+0.2` they would read as
`0.29999999999999`). When you need more than 12 digits, ask GIAC for a
multiprecision value with `Giac.Commands.evalf(x, n)`, or keep the input
exact: `1/10`, `exact(0.1)` and Julia's `1//10` stay exact rationals through
GIAC, and `to_julia` gives them back as `1//10`.

**Multiprecision reals (`REAL`) are read from their decimal**, which carries
all their digits; `float` keeps the `BigFloat` precision the decimal implies.

**Fractions (`FRAC`)** read as `Rational{Int64}`, or `Rational{BigInt}` when a
part does not fit a machine integer. GIAC stores a complex number with a
rational part as a fraction whose numerator is a Gaussian integer, so such a
number reads as a `Complex` of `Rational`s:

```julia
to_julia(giac_eval("(3+2*i)/4"))       # 3//4 + 1//2*im
to_julia(giac_eval("[1/2, 1/3+i/4]"))  # Complex{Rational{Int64}}[1//2 + 0//1*im, 1//3 + 1//4*im]
Complex(giac_eval("(3+2*i)/4"))        # 3//4 + 1//2*im
Rational(giac_eval("(3+2*i)/4"))       # InexactError, as for Rational(3//4 + 1//2*im)
```

Before, these raised `ArgumentError` (the Gaussian numerator could not be
parsed as an integer), and `Complex(g)` of any fraction raised `MethodError`.

**GIAC's `epsilon` is left as it was.** GIAC's `evalf` of a `rootof` to `n`
digits sets `epsilon`, the tolerance of its numeric algorithms, to `10⁻ⁿ`
for the rest of the session; numeric integrals then return two estimates
instead of a value. `Giac.Commands.evalf(x, n)` and `invoke_cmd(:evalf, x, n)`
put `epsilon` back afterwards, and so does `to_julia`, which reduces a
constant with `evalf(x, 18)`. Assigning `epsilon` yourself
(`giac_eval("epsilon:=1e-8")`) is unaffected.

### Core Functions

| Function | Description |
|----------|-------------|
| `giac_eval(expr)` | Evaluate a GIAC expression string |
| `invoke_cmd(cmd, args...)` | Invoke any GIAC command dynamically |
| `to_julia(expr)` | Convert GiacExpr to Julia type |
