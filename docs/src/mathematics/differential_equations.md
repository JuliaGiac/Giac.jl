# Differential Equations

Giac.jl provides symbolic solving of ordinary differential equations (ODEs) using GIAC's `desolve` command. The package includes a `Differential` operator following SciML/ModelingToolkit conventions for expressing derivatives naturally, plus a deprecated `D` alias kept during the transition window.

## The `Differential` Operator

`Differential(var)` is the canonical, SciML-style partial-differentiation operator. It captures a single variable and is applied as a callable. For a mono-variable function declared with `@giac_var t u(t)`, `Differential(t)(u)` represents `u'(t)`. Repeated application gives higher orders; mixed variables compose for partial derivatives. See [Calculus](calculus.md) for a multi-variable walkthrough.

```julia
using Giac
using Giac.Commands: desolve

@giac_var t u(t)
Dt = Differential(t)

Dt(u)              # u'(t)
Dt(Dt(u))          # u''(t)  (adjacent same-var steps collapse)
```

### Comparison with raw GIAC syntax

| `Differential` form | Raw GIAC | Description |
|---|---|---|
| `Differential(t)(u)` | `diff(u(t), t)` | First derivative |
| `Differential(t)(Differential(t)(u))` | `diff(u(t), t, 2)` | Second derivative |
| `Differential(t)(u)(0) ~ 1` | `"u'(0)=1"` | Initial condition for `u'(0)` |

### Unicode identifiers

Function and variable names may use any Unicode letters that Julia and GIAC accept:

```julia
@giac_var 𝑧 ϕ(𝑧)
Dz = Differential(𝑧)
Dz(ϕ)        # diff(ϕ(𝑧), 𝑧)
Dz(Dz(ϕ))    # diff(ϕ(𝑧), 𝑧, 2)
```

### The deprecated `D` alias

Earlier versions of Giac.jl exposed a `D` operator (e.g. `D(u)`, `D(u, 2)`, `D(D(u))`). `D` is still available during a one-release deprecation window, with each call site emitting a `Base.depwarn` pointing to the canonical replacement. `D` will be removed in the next published release. See [`docs/migration/d_to_differential.md`](../migration/d_to_differential.md) for the full mapping table.

The one `D` call shape that *no longer works* even with a warning: `D(f)` for a multi-argument function like `@giac_var x y f(x, y)` now raises `ArgumentError` instead of silently differentiating against the first variable. Use `Differential(x)(f)` (or `Differential(y)(f)`) explicitly.

## First-Order ODEs

### Basic Example

Solve `τu' + u = U₀` with initial condition `u(0) = 1`:

```julia
using Giac
using Giac.Commands: desolve

@giac_var t u(t) tau U0
Dt = Differential(t)

# Define ODE: τu' + u = U₀
ode = tau * Dt(u) + u ~ U0

# Initial condition: u(0) = 1
initial = u(0) ~ 1

# Solve
result = desolve([ode, initial], t, :u)
# Returns: U0+(-U0+1)*exp(-t/tau)
```

### RC Circuit Example

```julia
@giac_var t V(t) R C Vs
Dt = Differential(t)

# Capacitor voltage ODE: RC·V' + V = Vs
ode = R * C * Dt(V) + V ~ Vs
initial = V(0) ~ 0

result = desolve([ode, initial], t, :V)
# Returns: Vs*(1-exp(-t/(R*C)))
```

## Second-Order ODEs

### Harmonic Oscillator

Solve `u'' + u = 0` with `u(0) = 1`, `u'(0) = 0`:

```julia
using Giac
using Giac.Commands: desolve

@giac_var t u(t)
Dt = Differential(t)

# Define ODE
ode = Dt(Dt(u)) + u ~ 0

# Initial conditions
u0 = u(0) ~ 1            # u(0) = 1
du0 = Dt(u)(0) ~ 0       # u'(0) = 0

# Solve
result = desolve([ode, u0, du0], t, :u)
# Returns: cos(t)
```

### Damped Oscillator

Solve `u'' + 2ζω₀u' + ω₀²u = 0`:

```julia
@giac_var t u(t) zeta omega0
Dt = Differential(t)

ode = Dt(Dt(u)) + 2*zeta*omega0*Dt(u) + omega0^2*u ~ 0
result = desolve([ode, u(0) ~ 1, Dt(u)(0) ~ 0], t, :u)
```

## Third-Order ODEs

Solve `y''' - y = 0` with `y(0) = 1`, `y'(0) = 1`, `y''(0) = 1`:

```julia
using Giac
using Giac.Commands: desolve

@giac_var t y(t)
Dt = Differential(t)

# Define ODE
ode = Dt(Dt(Dt(y))) - y ~ 0

# Initial conditions
y0 = y(0) ~ 1
dy0 = Dt(y)(0) ~ 1
d2y0 = Dt(Dt(y))(0) ~ 1

# Solve
result = desolve([ode, y0, dy0, d2y0], t, :y)
# Returns: exp(t)
```

## Using `Differential` in ODE Expressions

The `Differential` operator's result type supports arithmetic, making it natural to build ODE expressions:

```julia
@giac_var t u(t) a b c
Dt = Differential(t)

# Build complex ODE expressions
ode1 = Dt(Dt(u)) + a*Dt(u) + b*u ~ c
ode2 = Dt(Dt(u)) - 4*Dt(u) + 4*u ~ 0

# Combine with other GiacExpr
forcing = sin(t)
ode3 = Dt(Dt(u)) + u ~ forcing
```

## Important Notes

### Function Name as Symbol

When calling `desolve`, pass the function name as a **Symbol** (`:u`, `:y`) rather than the function expression (`u`, `y`):

```julia
# Correct
desolve([ode, u(0) ~ 1], t, :u)

# Incorrect - GIAC expects just the name, not u(t)
desolve([ode, u(0) ~ 1], t, u)  # May not work as expected
```

### Initial Conditions with `Differential`

The `Differential(t)(u)(0)` syntax creates an unevaluated derivative condition that GIAC interprets correctly:

```julia
Dt = Differential(t)
Dt(u)(0) ~ 1            # Creates "u'(0)=1" for GIAC
Dt(Dt(u))(0) ~ 0        # Creates "u''(0)=0" for GIAC
```

This works because the underlying `DerivativeExpr` is mono-variable. Point-evaluation syntax for partial derivatives of multi-variable functions (e.g. PDE boundary conditions) is not supported in this release; see spec 068 Open Questions for the planned path.

### Systems of ODEs

GIAC can solve systems of first-order ODEs:

```julia
@giac_var t x(t) y(t)
Dt = Differential(t)

# dx/dt = y, dy/dt = -x
sys = [Dt(x) ~ y, Dt(y) ~ -x]
initial = [x(0) ~ 1, y(0) ~ 0]

# Solve as a system (pass both variables)
result = desolve([sys..., initial...], t, [:x, :y])
```

## Physics Applications

### Exponential Decay

Model radioactive decay: `dN/dt = -λN`

```julia
@giac_var t N(t) lambda N0
Dt = Differential(t)

# Decay equation
ode = Dt(N) + lambda * N ~ 0
initial = N(0) ~ N0

result = desolve([ode, initial], t, :N)
# Returns: N0*exp(-lambda*t)
```

### Population Growth

Exponential growth model: `dP/dt = rP`

```julia
@giac_var t P(t) r P0
Dt = Differential(t)

ode = Dt(P) - r * P ~ 0
initial = P(0) ~ P0

result = desolve([ode, initial], t, :P)
# Returns: P0*exp(r*t)
```

### Newton's Law of Cooling

Temperature change: `dT/dt = -k(T - T_env)`

```julia
@giac_var t T(t) k T_env T0
Dt = Differential(t)

ode = Dt(T) + k * (T - T_env) ~ 0
initial = T(0) ~ T0

result = desolve([ode, initial], t, :T)
# Returns exponential approach to T_env
```

## Limitations

- **ODEs only**: GIAC's `desolve` is designed for ordinary differential equations. For PDEs, consider Symbolics.jl + MethodOfLines.jl or other specialized packages.
- **Symbolic solutions**: `desolve` finds closed-form analytical solutions when possible. For numerical solutions of ODEs, use DifferentialEquations.jl.

## API Reference

```@docs
Differential
D
DerivativeExpr
DerivativePoint
DerivativeCondition
expand_derivatives
```
