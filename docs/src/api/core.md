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
```

## Symbolic Variables

```@docs
@giac_var
@giac_several_vars
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
```

### Core Functions

| Function | Description |
|----------|-------------|
| `giac_eval(expr)` | Evaluate a GIAC expression string |
| `invoke_cmd(cmd, args...)` | Invoke any GIAC command dynamically |
| `to_julia(expr)` | Convert GiacExpr to Julia type |
