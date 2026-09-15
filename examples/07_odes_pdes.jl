### A Pluto.jl notebook ###
# v0.20.24

using Markdown
using InteractiveUtils

# ╔═╡ affa8790-1fd6-4467-bfda-23be0b73a882
begin
	using Pkg
	# Pkg.add(PackageSpec(url="https://github.com/s-celles/Giac.jl"))
	Pkg.develop(PackageSpec(path=".."))
end

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000001
begin
	using Giac
	using Giac.Commands: desolve, simplify
end

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000000
md"""
# Symbolic ODEs and PDEs with Giac.jl

Closed-form solutions of ordinary differential equations through GIAC's `desolve` command, expressed with the SciML/ModelingToolkit-style `Differential` operator (spec 068). The same operator builds partial-derivative expressions for partial differential equations, even though GIAC's `desolve` itself targets ODEs only — for full numerical PDE solutions, hand the symbolic problem off to `MethodOfLines.jl` or another PDE solver.

This notebook is reactive: change a coefficient or an initial condition and every downstream cell updates.

---

## 1. The `Differential` operator in two minutes

`Differential(var)` is a callable that captures a single differentiation variable. Apply it to any `GiacExpr` to obtain a partial derivative.

- **Function-form** operands (declared via `@giac_var f(x, y)`) → returns a `DerivativeExpr` that knows its differentiation history. Supports `~` to build equations and `(d)(0)` to build initial conditions.
- **Bare-expression** operands → returns a plain `GiacExpr` (already simplified by GIAC), matching SymPy's `diff(expr, var)`.

The two-argument shorthand `Differential(var, n)` matches Symbolics.jl's `Differential(x, 2)` form.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000002
@giac_var t x y u(t) y_t(t) Q(t) X(x) T(t) ψ(x, t) θ(x, y) τ U₀ ω₀ ζ Ω L R C V_s c α λ

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000003
md"""
For the rest of this notebook we'll alias the most common operator:
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000004
Dt = Differential(t)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000005
md"""
First and second time-derivatives of `u(t)`:
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000006
Dt(u)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000007
Dt(Dt(u))

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000008
md"""
Or equivalently with the n-th-order shorthand:
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000009
Differential(t, 2)(u)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-70000000000a
md"""
---

## 2. First-order linear ODE

**Problem.** Solve `τ u'(t) + u(t) = U₀` with `u(0) = 1`. This is the canonical first-order RC-charging equation.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000010
ode_1 = τ * Dt(u) + u ~ U₀

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000011
ic_1 = u(0) ~ 1

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000012
sol_1 = desolve([ode_1, ic_1], t, :u)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000013
md"""
The closed form: `u(t) = U₀ + (1 - U₀) · exp(-t/τ)` — what you'd derive by hand.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000014
md"""
---

## 3. Harmonic oscillator (second-order, undamped)

**Problem.** `u''(t) + u(t) = 0` with `u(0) = 1` and `u'(0) = 0`. Initial conditions for derivatives use the same `Differential(t)(u)(0)` syntax — internally a `DerivativePoint`.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000020
ode_2 = Dt(Dt(u)) + ω₀^2*u ~ 0

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000021
ic_2_pos = u(0) ~ 1

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000022
ic_2_vel = Dt(u)(0) ~ 0

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000023
sol_2 = desolve([ode_2, ic_2_pos, ic_2_vel], t, :u)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000024
md"""
Result: `cos(t)`. Try changing `ic_2_vel` to `Dt(u)(0) ~ 1` and the solution becomes `sin(t) + cos(t)` (or the equivalent canonical form GIAC chooses).
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000025
md"""
---

## 4. Damped oscillator (second-order, with friction)

**Problem.** `u''(t) + 2 ζ ω₀ u'(t) + ω₀² u(t) = 0` — the standard damped-oscillator form. The qualitative behavior depends on `ζ` (under-damped, critically-damped, over-damped). We solve the symbolic case with arbitrary `ζ` and `ω₀`.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000030
ode_3 = Dt(Dt(u)) + 2*ζ*ω₀*Dt(u) + ω₀^2 * u ~ 0

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000031
sol_3 = desolve([ode_3, u(0) ~ 1, Dt(u)(0) ~ 0], t, :u)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000032
md"""
GIAC returns the closed form in terms of `ζ` and `ω₀`. The result is large but exact — and you can simplify or substitute numeric values to see specific regimes.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000033
md"""
---

## 5. Third-order ODE

**Problem.** `y'''(t) - y(t) = 0` with `y(0) = 1`, `y'(0) = 1`, `y''(0) = 1`. The `Differential(t, n)` shorthand keeps the cell readable for higher orders.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000040
ode_4 = Differential(t, 3)(y_t) - y_t ~ 0

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000041
sol_4 = desolve(
	[ode_4,
	 y_t(0) ~ 1,
	 Dt(y_t)(0) ~ 1,
	 Dt(Dt(y_t))(0) ~ 1],
	t, :y_t,
)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000042
md"""
The unique solution is `exp(t)`.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000043
md"""
---

## 6. RLC circuit (driven, second-order)

**Problem.** A series RLC circuit driven by a constant source: `L Q''(t) + R Q'(t) + Q(t)/C = V_s`. Solve for the charge `Q(t)` with `Q(0) = 0` and `I(0) = Q'(0) = 0`.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000051
ode_5 = L*Dt(Dt(Q)) + R*Dt(Q) + Q/C ~ V_s

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000052
sol_5 = desolve([ode_5, Q(0) ~ 0, Dt(Q)(0) ~ 0], t, :Q)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000053
md"""
The result is symbolic in `L`, `R`, `C`, `V_s`. Substitute numeric values for any parameter to inspect the under/over/critically-damped regime — exactly as in §4.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000054
md"""
---

## 7. Forced oscillator (non-homogeneous second-order ODE)

**Problem.** A harmonic oscillator with a sinusoidal driving force at angular frequency `Ω`: `u''(t) + ω₀² u(t) = sin(Ω t)`. The closed form has a particular solution that grows linearly in `t` exactly when `Ω = ω₀` (resonance) — `desolve` returns the symbolic answer in `Ω` and `ω₀` so you can compare regimes.
"""

# ╔═╡ fc3e0b7a-bb9b-4e35-ad05-d3b929daa200
ode_6 = [Dt(Dt(u)) + ω₀^2 * u ~ sin(Ω * t), u(0) ~ 0, Dt(u)(0) ~ 0]

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000062
sol_forced = desolve(
	ode_6,
	t, :u,
)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000063
md"""
The result is symbolic in `Ω` and `ω₀`. Substitute `Ω => ω₀` and the solution diverges — that's the resonance singularity.

> **Note on systems of ODEs.** GIAC's `desolve` solves single ODEs (and systems through some alternative entry points outside this notebook). If you need a coupled-system solver with closed-form output across vector unknowns, [`Symbolics.jl`](https://github.com/JuliaSymbolics/Symbolics.jl) + [`MTK.jl`](https://github.com/SciML/ModelingToolkit.jl) is the better tool — and `to_symbolics` / `to_giac` let you round-trip parts of the problem through GIAC.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000064
md"""
---

## 8. Building partial differential equations

`Differential` composes for partial derivatives just as cleanly. Declare a function of multiple variables and chain operators:
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000071
Dx = Differential(x)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000072
md"""
**Heat equation** (1D): `∂ψ/∂t = α · ∂²ψ/∂x²`.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000073
heat_eq = Dt(ψ) ~ α * Differential(x, 2)(ψ)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000074
md"""
**Wave equation** (1D): `∂²ψ/∂t² = c² · ∂²ψ/∂x²`.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000075
wave_eq = Differential(t, 2)(ψ) ~ c^2 * Differential(x, 2)(ψ)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000076
md"""
**Steady-state 2D heat equation** (Laplace's equation for the temperature field `θ(x, y)` in a heat-conducting plate at thermodynamic equilibrium, no time dependence): `∂²θ/∂x² + ∂²θ/∂y² = 0`.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000077
laplace_eq = Differential(x, 2)(θ) + Differential(y, 2)(θ) ~ 0

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000078
md"""
**Mixed second-order partials.** `∂²ψ/∂x∂t` records two distinct steps; same-variable applications collapse:
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000079
Dt(Dx(ψ))

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-70000000007a
Dx(Dx(ψ))

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-70000000007b
md"""
The left value is the cross partial `∂²ψ/∂x∂t` (two steps preserved). The right value is `∂²ψ/∂x²` (steps collapsed because both are on `x`).
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-70000000007c
md"""
---

## 9. What about solving PDEs symbolically?

GIAC's `desolve` is an **ODE** solver — passing a PDE expression to it does *not* in general return a closed-form PDE solution. For closed-form PDE solutions, a few options:

1. **Separation of variables by hand.** Substitute `ψ(x, t) = X(x) · T(t)`, equate the ratios, and solve the two resulting ODEs with `desolve`. The notebook below sketches this for the heat equation.
2. **Symbolics.jl + MethodOfLines.jl.** For numerical PDE solutions, convert the symbolic PDE expression to Symbolics.jl (`to_symbolics`) and discretize.
3. **Specific known forms.** GIAC's `pde_separate` (when available) can do separation of variables for selected PDEs.

Below: the heat equation reduced to two ODEs by separation of variables.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000081
md"""
Spatial part: `X''(x) + λ · X(x) = 0`. Pick `λ > 0` (we get sinusoidal modes).
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000082
spatial_ode = Differential(x, 2)(X) + λ * X ~ 0

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000083
spatial_sol = desolve([spatial_ode, X(0) ~ 0, Dx(X)(0) ~ 1], x, :X)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000084
md"""
Temporal part: `T'(t) + α · λ · T(t) = 0` — exponential decay with rate `α λ`.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000085
temporal_ode = Dt(T) + α * λ * T ~ 0

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000086
temporal_sol = desolve([temporal_ode, T(0) ~ 1], t, :T)

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000087
md"""
The full mode `ψ(x, t) = X(x) · T(t)` decays in time with rate `α λ` while oscillating in space — the standard heat-equation diffusion mode. A complete solution sums infinitely many such modes weighted by the boundary data.
"""

# ╔═╡ c2d3e4f5-a6b7-8901-cdef-700000000090
md"""
---

## 10. Migration note: `D` vs `Differential`

The earlier `D` operator (e.g. `D(u)`, `D(u, 2)`, `D(D(u))`) still works during the deprecation window with a `Base.depwarn`. The mapping to `Differential` is mechanical:

| Old `D` form | New `Differential` form |
|---|---|
| `D(u)` | `Differential(t)(u)` |
| `D(u, 2)` | `Differential(t, 2)(u)` *or* `Differential(t)(Differential(t)(u))` |
| `D(D(u))` | `Differential(t, 2)(u)` |
| `D(u)(0) ~ 1` | `Differential(t)(u)(0) ~ 1` |

The full table — including the multi-variable cases that the old `D` could not handle — lives in the [migration guide](../docs/src/migration/d_to_differential.md).

For a notebook that compares Giac.jl with Symbolics.jl side-by-side, see [`06_symbolics_bridge.jl`](06_symbolics_bridge.jl).
"""

# ╔═╡ Cell order:
# ╟─affa8790-1fd6-4467-bfda-23be0b73a882
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000000
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000001
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000002
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000003
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000004
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000005
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000006
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000007
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000008
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000009
# ╟─c2d3e4f5-a6b7-8901-cdef-70000000000a
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000010
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000011
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000012
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000013
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000014
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000020
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000021
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000022
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000023
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000024
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000025
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000030
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000031
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000032
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000033
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000040
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000041
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000042
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000043
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000051
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000052
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000053
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000054
# ╠═fc3e0b7a-bb9b-4e35-ad05-d3b929daa200
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000062
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000063
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000064
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000071
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000072
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000073
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000074
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000075
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000076
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000077
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000078
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000079
# ╠═c2d3e4f5-a6b7-8901-cdef-70000000007a
# ╟─c2d3e4f5-a6b7-8901-cdef-70000000007b
# ╟─c2d3e4f5-a6b7-8901-cdef-70000000007c
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000081
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000082
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000083
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000084
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000085
# ╠═c2d3e4f5-a6b7-8901-cdef-700000000086
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000087
# ╟─c2d3e4f5-a6b7-8901-cdef-700000000090
