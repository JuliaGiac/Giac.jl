# Calculus

Giac.jl provides powerful symbolic calculus capabilities including differentiation, integration, limits, and Taylor series expansion.

## Setup

```julia
using Giac
using Giac.Commands: diff, integrate, limit, series

@giac_var x y
```

## Differentiation

### Basic Derivatives

Compute derivatives using the `diff` command:

```julia
diff(x^2, x)
# Output: 2*x

diff(x^3, x)
# Output: 3*x^2
```

### Higher-Order Derivatives

Compute second, third, or higher-order derivatives by specifying the order:

```julia
diff(x^4, x, 2)   # Second derivative
# Output: 12*x^2

diff(x^5, x, 3)   # Third derivative
# Output: 60*x^2
```

### Chain Rule

The chain rule is applied automatically:

```julia
diff(sin(x^2), x)
# Output: 2*x*cos(x^2)
```

### Product Rule

Derivatives of products are handled automatically:

```julia
diff(x * sin(x), x)
# Output: sin(x)+x*cos(x)
```

### Partial Derivatives

For multivariable functions, specify the variable:

```julia
@giac_var x y

diff(x^2 * y^3, x)
# Output: 2*x*y^3

diff(x^2 * y^3, y)
# Output: 3*x^2*y^2
```

### Using the `Differential` operator

Beyond the function-form `Giac.Commands.diff`, Giac.jl also exposes a SciML/ModelingToolkit-style operator: `Differential(var)` is a callable that captures a single differentiation variable and applies partial differentiation to its operand. This pairs naturally with declared functions (`@giac_var f(x, y)`) and with bare symbolic expressions.

```julia
using Giac

@giac_var x y t f(x, y) u(t)

# Bare-expression form (matches SymPy.jl `diff(expr, var)`)
Differential(x)(x^2 + y*x)        # Returns: 2*x + y
Differential(x)(sin(x) * exp(x))   # Returns: cos(x)*exp(x) + sin(x)*exp(x)

# Function-form: declared function, returns a DerivativeExpr
Dx = Differential(x)
Dy = Differential(y)
Dx(f)               # ∂f/∂x
Dy(Dx(f))           # ∂²f/∂y∂x  (cross partial — see "Notation" below)
Dx(Dx(f))           # ∂²f/∂x²   (adjacent same-var steps collapse)

# Mono-variable functions work the same way
Dt = Differential(t)
Dt(u)               # u'(t)
Dt(Dt(u))           # u''(t)

# Two-argument shorthand for n-th order (matches Symbolics.jl's Differential(x, 2))
Differential(x, 3)(f)             # ∂³f/∂x³  — same as Dx(Dx(Dx(f)))
Differential(t, 2)(u)             # u''(t)   — same as Dt(Dt(u))
Differential(x, 2)(x^3)           # 6*x      — bare-expression second derivative
```

#### Notation: right-to-left Leibniz convention

In partial-derivative output (`Base.show` and the math comments above),
Giac.jl uses the **right-to-left Leibniz convention**: in `∂ⁿf/∂v₁…∂vₙ`,
the **rightmost** variable in the denominator is applied **first**, the
**leftmost** last. This matches the operator product
`(∂/∂v₁)·…·(∂/∂vₙ) f` read as a chain of left-multiplications:
`Differential(y)(Differential(x)(f))` (apply `Differential(x)` first, then
`Differential(y)`) is written `∂²f/∂y∂x` and pretty-prints as
`D: ∂²f/∂y∂x`. By Schwarz/Clairaut the value is symmetric for
sufficiently smooth `f`, but the notation, the `Base.show` output, and the
internal `DerivativeExpr.steps` field track the order of application.

The function-form path returns a `DerivativeExpr` that records the differentiation history as an ordered sequence of `(variable, order)` steps (innermost-first). The bare-expression path returns a plain `GiacExpr` (already simplified by GIAC). For high-order derivatives (`n ≥ 4`), the human-readable display switches from primes to math-convention parenthesized superscripts: `D(u, 5)` shows as `u⁽⁵⁾(t)` rather than `u'''''(t)`. See [Differential Equations](differential_equations.md) for ODE/PDE workflows and [the migration guide](../migration/d_to_differential.md) for porting from the deprecated `D` operator.

## Integration

### Indefinite Integrals

Compute antiderivatives using the `integrate` command:

```julia
integrate(x^2, x)
# Output: x^3/3

integrate(sin(x), x)
# Output: -cos(x)

integrate(exp(x), x)
# Output: exp(x)
```

### Definite Integrals

Specify bounds for definite integrals:

```julia
# ∫₀¹ x² dx = 1/3
integrate(x^2, x, 0, 1)
# Output: 1/3

# ∫₀^π sin(x) dx = 2
integrate(sin(x), x, 0, pi)
# Output: 2
```

### Integration Techniques

GIAC automatically applies various integration techniques:

```julia
# Integration by parts
integrate(x * exp(x), x)
# Output: (x-1)*exp(x)

# Partial fractions
integrate(1/(x^2-1), x)
# Uses partial fraction decomposition

# Trigonometric integrals
integrate(sin(x)^2, x)
# Output: x/2-sin(2*x)/4
```

## Limits

### Basic Limits

Compute limits using the `limit` command:

```julia
# Classic limit: sin(x)/x as x→0
limit(sin(x)/x, x, 0)
# Output: 1
```

### Limits at Infinity

```julia
@giac_var inf  # Create infinity symbol

limit(1/x, x, inf)
# Output: 0

limit((x^2+1)/(2*x^2-3), x, inf)
# Output: 1/2
```

### L'Hôpital's Rule Cases

GIAC automatically handles indeterminate forms:

```julia
# 0/0 form
limit((exp(x)-1)/x, x, 0)
# Output: 1

# ∞/∞ form
limit(ln(x)/x, x, inf)
# Output: 0
```

## Taylor Series

### Series Expansion

Expand functions as Taylor series using the `series` command:

```julia
# exp(x) around x=0, order 4
series(exp(x), x, 0, 4)
# Output: 1+x+x^2/2+x^3/6+x^4/24+O(x^5)

# sin(x) around x=0, order 5
series(sin(x), x, 0, 5)
# Output: x-x^3/6+x^5/120+O(x^6)

# cos(x) around x=0, order 4
series(cos(x), x, 0, 4)
# Output: 1-x^2/2+x^4/24+O(x^5)
```

### Series Around Other Points

Expand around a point other than zero:

```julia
# exp(x) around x=1
series(exp(x), x, 1, 3)
# Expansion around x=1
```

## Advanced Topics

### Gradient and Hessian

For multivariable calculus:

```julia
using Giac.Commands: gradient, hessian

@giac_var x y

f = x^2 + x*y + y^2

# Gradient: [∂f/∂x, ∂f/∂y]
gradient(f, [x, y])  # ToFix
# Output: [2*x+y, x+2*y]

# Hessian matrix
hessian(f, [x, y])
# Output: [[2, 1], [1, 2]]
```

### Implicit Differentiation

```julia
using Giac.Commands: implicitdiff

# For x² + y² = 1, find dy/dx
implicitdiff(x^2 + y^2 - 1, x, y)  # ToFix
# Output: -x/y
```

## Notes

- All calculus operations work symbolically, not numerically
- For numerical integration, convert results using `to_julia` and use Julia's quadrature packages
- The `diff` command uses Leibniz notation internally
- Series expansions include the order term `O(x^n)` by default
