# Migrating from `D` to `Differential`

Spec 068 introduces `Differential` as the canonical, SciML/ModelingToolkit-style
partial-differentiation operator and deprecates the legacy `D` operator. This
guide maps every `D(...)` call shape to its `Differential(...)` replacement so
you can update existing notebooks, scripts, and downstream packages
mechanically.

## Why migrate

Three reasons:

1. **Multi-variable support**. `D(f)` on a multi-argument function like
   `@giac_var x y f(x, y)` used to silently differentiate with respect to the
   first variable (`x`), producing a wrong answer that looked plausible.
   Calling `D(f)` now raises `ArgumentError`. `Differential(x)(f)` makes the
   choice explicit.
2. **Bare-expression operands**. `Differential(x)(x^2 + y*x)` returns
   `2*x + y` directly. `D` only accepts function-form expressions like
   `u(t)` — bare expressions raise an error. `Differential` matches what
   SymPy.jl's `diff(expr, var)` and Symbolics.jl's `Differential` already do.
3. **Composition reads naturally**. `Differential(y)(Differential(x)(f))`
   tracks the cross partial `∂²f/∂y∂x` (right-to-left Leibniz convention:
   the rightmost variable is applied first — `Differential(x)` is applied
   before `Differential(y)`); mixed orders
   (`Differential(x)(Differential(y)(Differential(x)(f)))`) work the same way.

## Timeline

`D` is deprecated in `0.15.0` and will be removed in the next published
release after `0.15.0`. Each unique `D(...)` call site emits exactly one
`Base.depwarn` per Julia session pointing to the canonical replacement.

## Side-by-side mapping

For mono-variable functions (`@giac_var t u(t)`):

| Deprecated `D` form | Canonical `Differential` form |
|---|---|
| `D(u)` | `Differential(t)(u)` |
| `D(u, 2)` | `Differential(t, 2)(u)` *or* `Differential(t)(Differential(t)(u))` |
| `D(D(u))` | `Differential(t, 2)(u)` *or* `Differential(t)(Differential(t)(u))` |
| `D(u, 3)` | `Differential(t, 3)(u)` *or* `Differential(t)(Differential(t)(Differential(t)(u)))` |
| `D(u)(0) ~ 1` | `Differential(t)(u)(0) ~ 1` (initial-condition syntax unchanged) |

The two-argument shorthand `Differential(t, n)` matches Symbolics.jl's `Differential(x, 2)` form and is exactly equivalent to applying `Differential(t)` `n` times. Use whichever reads better in your code — they produce the same `DerivativeExpr` value.

For multi-variable functions (`@giac_var x y f(x, y)`):

| Was (silently broken or unsupported) | Now |
|---|---|
| `D(f)` (silently picked `x`!) | `Differential(x)(f)` (explicit) or `Differential(y)(f)` |
| Not expressible directly with `D` | `Differential(y)(Differential(x)(f))` for `∂²f/∂y∂x` |
| Not expressible directly with `D` | `Differential(x)(Differential(x)(f))` for `∂²f/∂x²` |
| `D(f, x)` (transitional alias, deprecated) | `Differential(x)(f)` |
| `D(f, x, 2)` (transitional alias, deprecated) | `Differential(x)(Differential(x)(f))` |

For bare expressions:

| Was (raised) | Now |
|---|---|
| `D(x^2 + y*x)` (raised "requires a function expression") | `Differential(x)(x^2 + y*x) → 2*x + y` |
| `D(sin(x) * exp(x))` (raised) | `Differential(x)(sin(x) * exp(x))` |

## Initial conditions for ODEs

The mono-variable initial-condition syntax is unchanged because `Differential`
returns the same `DerivativeExpr` value:

```julia
using Giac
using Giac.Commands: desolve

@giac_var t u(t)
Dt = Differential(t)

ode = Dt(Dt(u)) + u ~ 0
ic1 = u(0) ~ 1
ic2 = Dt(u)(0) ~ 0          # u'(0) = 0  — produces "u'(0)=0" via DerivativePoint

desolve([ode, ic1, ic2], t, :u)   # → cos(t)
```

PDE-style point-evaluation (e.g., `Differential(x)(f)(0, 0) ~ 1`) is *not*
supported in this release and raises a clear error. See spec 068 Open
Questions for the planned path.

## `Differential` collision with `Symbolics.jl`

Symbolics.jl exports a type also called `Differential`. When both packages are
loaded, Julia warns about the ambiguity and requires you to qualify the name:

```julia
using Giac
using Symbolics

@giac_var x y f(x, y)
Giac.Differential(x)(f)            # Giac's path
@variables a b
Symbolics.Differential(a)          # Symbolics' path
```

`Giac.Differential` and `Symbolics.Differential` are independent types — there
is no implicit interop in this release. This is the standard Julia
ambiguity-resolution pattern, the same one used across the SciML stack
(`DifferentialEquations.solve` vs `DifferentialEquations.ODESolution.solve`,
etc.). A bridging extension can be added later if a concrete need surfaces.

## Mechanical migration recipe

1. **Search-and-replace** simple `D(u) → Differential(t)(u)` in your codebase
   (the variable `t` is whatever single argument `u` was declared with).
2. For `D(u, 2)`, replace with `Differential(t)(Differential(t)(u))` or assign
   `Dt = Differential(t)` once and write `Dt(Dt(u))`.
3. For `D(D(u))` chained calls, rewrite as `Dt(Dt(u))`.
4. For multi-variable functions where you previously called `D(f)`, decide
   which variable you actually want and write `Differential(x)(f)` or
   `Differential(y)(f)` explicitly.
5. Keep initial-condition syntax untouched: `D(u)(0) ~ 1` becomes
   `Differential(t)(u)(0) ~ 1`.

## Bare-expression migration (new capability)

If you were manually shelling out to `Giac.Commands.diff(expr, var)` to
differentiate bare expressions, you can now write:

```julia
using Giac
@giac_var x y

# Before
result = Giac.Commands.diff(x^2 + y*x, x)

# After
result = Differential(x)(x^2 + y*x)   # → 2*x + y
```

Both still work; `Differential` is the recommended form going forward.
