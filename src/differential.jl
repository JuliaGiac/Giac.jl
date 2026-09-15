# Spec 068 — multivar D operator
# Differential operator (canonical, SciML-style) — applies partial differentiation
# to function-form expressions and to bare GiacExpr operands.

"""
    Differential(var::GiacExpr)
    Differential(var::GiacExpr, order::Int)

Canonical partial-differentiation operator, SciML/ModelingToolkit-style.

`Differential(var)` captures a single differentiation variable; the resulting
callable applies a first-order partial derivative to its operand. The two-argument
form `Differential(var, n)` produces an operator that applies the `n`-th order
partial derivative in one step — equivalent to applying `Differential(var)` `n`
times — and matches Symbolics.jl's `Differential(x, n)` shape.

# Two operand forms

- **Function-form**: `Differential(x)(f)` for `@giac_var x y f(x,y)` returns a
  `DerivativeExpr` representing `∂f/∂x`. Compose by chaining:
  `Differential(y)(Differential(x)(f))` is `∂²f/∂y∂x` (see *Notation*
  below). The order-2 shape `Differential(x, 2)(f)` produces the same result
  as `Differential(x)(Differential(x)(f))` (steps collapse).
- **Bare-expression**: `Differential(x)(x^2 + y*x)` returns a plain `GiacExpr`
  (already simplified by GIAC) — `2*x + y` in this case. The order-2 shape
  `Differential(x, 2)(x^3)` returns `6*x` (after simplification). Aligns with
  SymPy.jl's `diff(expr, var)` and Symbolics.jl's `Differential`.

# Notation (right-to-left Leibniz)

`Giac.jl` uses the right-to-left Leibniz convention for `∂ⁿf/∂v₁…∂vₙ`:
the **rightmost** variable is applied **first**, the **leftmost** last —
consistent with the operator product `(∂/∂v₁)·…·(∂/∂vₙ) f`. So
`Differential(y)(Differential(x)(f))` (apply `Differential(x)` first, then
`Differential(y)`) is written `∂²f/∂y∂x`, and pretty-printed as `D: ∂²f/∂y∂x`.
By Schwarz/Clairaut the value is symmetric for sufficiently smooth `f`, but
the notation, the `Base.show` output, and the `steps` field track the order
of application.

# Composition

Repeated application on the same variable collapses adjacent steps:
`Differential(x)(Differential(x)(f))` stores `[("x", 2)]` rather than
`[("x", 1), ("x", 1)]`. Mixed variables compose freely:
`Differential(y)(Differential(x)(f))` stores `[("x", 1), ("y", 1)]`
(innermost-first) and prints as `diff(diff(f(x,y),x),y)` for GIAC.

The operators `^`, `*`, and `∘` are also supported for compact composition,
matching Symbolics.jl: `Differential(t)^2 === Differential(t, 2)`,
`Differential(y) * Differential(x) ≡ Differential(y) ∘ Differential(x)`, and
`Differential(t)^0 === identity`.

# Examples

```julia
using Giac
@giac_var x y t f(x, y) u(t)

Differential(x)(f)              # ∂f/∂x
Differential(y)(Differential(x)(f))  # ∂²f/∂y∂x  (x first, y next)

Differential(t)(u)              # u'(t)  (mono-variable case)

# Order-n shorthand (Symbolics.jl-style)
Differential(t, 2)(u)           # u''(t)  — same as Differential(t)(Differential(t)(u))
Differential(x, 3)(f)           # ∂³f/∂x³

Differential(x)(x^2 + y*x)      # 2*x + y  (bare expression)
Differential(x, 2)(x^3)         # 6*x      (bare expression, second derivative)
```

# Name collision with Symbolics.jl

`Symbolics.Differential` exists too. When both packages are loaded, qualify:
`Giac.Differential(x)(f)` vs `Symbolics.Differential(x)`. The two are
independent types — there is no implicit interop in this release. See
`docs/migration/d_to_differential.md` for the recipe.

# See also
- [`D`](@ref): Deprecated mono-variable operator. `D` is being removed in the
  next published release; migrate `D(u) → Differential(t)(u)`.
- [`DerivativeExpr`](@ref): The function-form result type.
"""
struct Differential
    var::GiacExpr
    order::Int

    function Differential(var::GiacExpr, order::Int = 1)
        order >= 1 || throw(ArgumentError("Differential order must be ≥ 1, got: $order"))
        return new(var, order)
    end
end

function Base.show(io::IO, D::Differential)
    if D.order == 1
        print(io, "Differential(", D.var, ")")
    else
        print(io, "Differential(", D.var, ", ", D.order, ")")
    end
end

# Application on a GiacExpr: dispatches between function-form (returns
# DerivativeExpr) and bare-expression (returns plain GiacExpr via GIAC's diff).
function (D::Differential)(operand::GiacExpr)
    parsed = _parse_function_args(string(operand))
    if parsed === nothing
        # Bare-expression branch (spec 068 US4): delegate to GIAC's diff(expr, var, n).
        # Returns a plain GiacExpr (already simplified by GIAC) — no DerivativeExpr
        # wrapper because there is no function-name / multi-step accounting to track.
        result = operand
        for _ in 1:D.order
            result = Commands.diff(result, D.var)
        end
        return result
    end
    funcname, _args = parsed
    var_str = string(D.var)
    return DerivativeExpr(operand, funcname, Tuple{String, Int}[(var_str, D.order)])
end

# Composition: append a step to an existing DerivativeExpr.
# `Differential(x, n)(d)` adds an n-order step against `x` to d.steps,
# collapsing if the previous step is on the same variable.
function (D::Differential)(d::DerivativeExpr)
    var_str = string(D.var)
    new_steps = _append_step(d.steps, (var_str, D.order))
    return DerivativeExpr(d.base_expr, d.funcname, new_steps)
end

# Symbolics.jl-style algebraic surface on Differential operators.
# `Differential(var)^n` yields the n-th order operator (n == 0 → identity, as
# in Symbolics). Composition via `*` and `∘` (Julia's generic ∘ already does
# the right thing on callables, but we add an explicit method so `*` can
# delegate uniformly and dispatch is clear in stack traces).

"""
    Base.:^(D::Differential, n::Integer) -> Differential | typeof(identity)

Return a `Differential` whose order is multiplied by `n`. Mirrors
Symbolics.jl: `Differential(x)^n === Differential(x, D.order * n)` for `n ≥ 1`,
and `Differential(x)^0 === identity` (the identity function).

`n` must be non-negative. Negative powers are not defined (anti-derivative
would require an explicit constant of integration).
"""
function Base.:^(D::Differential, n::Integer)
    n >= 0 || throw(ArgumentError("Differential^n requires n ≥ 0, got: $n"))
    n == 0 && return identity
    return Differential(D.var, D.order * n)
end

"""
    Base.:*(D1::Differential, D2::Differential) -> ComposedFunction

Compose two `Differential` operators: `(D1 * D2)(f) == D1(D2(f))`. Mirrors
Symbolics.jl's `Differential * Differential` and falls back to Julia's
generic `ComposedFunction` so applying the result on a `GiacExpr` or
`DerivativeExpr` reuses the existing `Differential` call-site logic
(including same-variable step collapse).
"""
Base.:*(D1::Differential, D2::Differential) = D1 ∘ D2

"""
    expand_derivatives(x) -> x

Force evaluation of any lazy derivative wrapper, returning a plain `GiacExpr`.

For `Differential(var)(f)` where `f` is a declared user function (`DerivativeExpr`),
`expand_derivatives` calls GIAC's `diff` and returns the resulting `GiacExpr`. For
everything else (already a `GiacExpr` produced by Giac.jl's eager bare-expression
branch, or any value not wrapped in `DerivativeExpr`), it is the identity — so
code written in the Symbolics.jl style (`expand_derivatives(Differential(x)(expr))`)
stays correct on Giac.jl without behavioral change.

# Examples

```julia
@giac_var x y f(x, y)

expand_derivatives(x^2 + y)            # identity → x^2+y
expand_derivatives(Differential(x)(x^2))  # identity → 2*x (already a GiacExpr)
expand_derivatives(Differential(x)(f))    # → diff(f(x,y),x) as a GiacExpr
```

# See also
- [`Differential`](@ref): The operator producing lazy or eager derivatives.
- [`DerivativeExpr`](@ref): The lazy function-form derivative wrapper.
"""
expand_derivatives(x) = x
expand_derivatives(d::DerivativeExpr) = _to_giac_expr(d)
