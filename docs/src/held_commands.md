# Held Commands

Held commands let you build and display mathematical expressions **without evaluating them**. This is useful for:
- Showing what computation will be performed before running it
- Educational presentations with proper mathematical notation
- Step-by-step mathematical exploration in notebooks

## Basic Usage

```julia
using Giac
using Giac.Commands: hold_cmd, release

@giac_var x t s n z

# Hold a command (no execution occurs)
h = hold_cmd(:integrate, x^2, x)
# In notebooks: renders as ∫ x² dx

# Execute when ready
result = release(h)
# Returns: x³/3
```

## Specialized LaTeX Rendering

The following commands render with standard mathematical notation in LaTeX-capable environments (Jupyter, Pluto):

### Integration

```julia
# Indefinite integral: ∫ f dx
hold_cmd(:integrate, sin(x), x)

# Definite integral: ∫₀¹ f dx
hold_cmd(:integrate, x^2, x, 0, 1)
```

### Differentiation (Leibniz notation)

```julia
# First derivative: d/dx f
hold_cmd(:diff, x^3, x)

# Higher-order: d²/dx² f
hold_cmd(:diff, x^3, x, 2)
```

### Laplace Transform

```julia
# Forward: ℒ{f}(s)
hold_cmd(:laplace, exp(-t), t, s)

# Inverse: ℒ⁻¹{F}(t)
hold_cmd(:invlaplace, 1/(s+1), s, t)
# Also works with :ilaplace
```

### Z-Transform

```julia
# Forward: 𝒵{f}(z)
hold_cmd(:ztrans, n^2, n, z)

# Inverse: 𝒵⁻¹{F}(n)
hold_cmd(:invztrans, z/(z-1), z, n)
```

### Limits

```julia
# Basic limit: lim_{x→0} sin(x)/x
hold_cmd(:limit, sin(x)/x, x, 0)

# Limit at infinity: lim_{x→+∞} 1/x
hold_cmd(:limit, 1/x, x, Inf)

# One-sided limits (direction: 1 for right, -1 for left)
hold_cmd(:limit, sign(x), x, 0, 1)   # lim_{x→0⁺}
hold_cmd(:limit, sign(x), x, 0, -1)  # lim_{x→0⁻}
```

### Sums and Products

```julia
# Finite sum: Σ_{n=1}^{17} 1/n²
hold_cmd(:sum, 1/n^2, n, 1, 17)

# Infinite sum (Basel problem): Σ_{n=1}^{∞} 1/n²
hold_cmd(:sum, 1/n^2, n, 1, Inf)

# Product: Π_{k=1}^{n} k
hold_cmd(:product, k, k, 1, n)
```

### Riemann Sums

```julia
# Renders as: lim_{n→+∞} Σ_{k=0}^{n-1} 1/(n+k)
hold_cmd(:sum_riemann, 1/(n+k), [n, k])
```

## Generic Commands

Commands without specialized rendering use function-call notation:

```julia
hold_cmd(:factor, x^2 - 1)     # Renders as: factor(x² - 1)
hold_cmd(:simplify, sin(x)^2)  # Renders as: simplify(sin²(x))
```

## Hold-Display-Release Workflow

```julia
# Step 1: Build the expression
h = hold_cmd(:integrate, exp(-t) * sin(t), t)

# Step 2: Display it (automatic in notebooks)
display(h)  # Shows: ∫ e⁻ᵗ sin(t) dt

# Step 3: Execute when ready
result = release(h)  # Computes the integral
display(result)       # Shows the evaluated result
```

## Equation Display with `~`

Held commands support the `~` (tilde) equation operator, enabling side-by-side display
of unevaluated and evaluated forms:

```julia
using Giac
using Giac.Commands: hold_cmd, release, eigenvals

M = GiacMatrix([[1, 2], [3, 4]])

# Show "eigenvals([[1,2],[3,4]]) = [computed result]"
h = hold_cmd(:eigenvals, M)
eq = h ~ eigenvals(M)

# Also works with the held command on the right
eq = eigenvals(M) ~ h

# Between two held commands
eq = hold_cmd(:factor, x^2 - 1) ~ hold_cmd(:expand, (x-1)*(x+1))

# With numbers
eq = hold_cmd(:det, M) ~ -2
```

All type combinations are supported: `HeldCmd ~ GiacExpr`, `GiacExpr ~ HeldCmd`,
`HeldCmd ~ HeldCmd`, `HeldCmd ~ Number`, and `Number ~ HeldCmd`.

## API Reference

```@docs
HeldCmd
Giac.Commands.hold_cmd
Giac.Commands.release
```

## Unevaluated input

`giac_eval` parses *and evaluates*, and evaluation already rewrites some
expressions: `giac_eval("sqrt(x^2)")` is `abs(x)` before any `simplify`, and
`x` under `assume(x > 0)`. So the result of `simplify(giac_eval(s))` mixes what
evaluation did with what `simplify` did. To tell the steps apart, hold the
input with GIAC's `quote`, then apply each step explicitly:

```julia
@giac_var x
received  = giac_eval("quote(sqrt(x^2))")   # sqrt(x^2): the input as written
evaluated = invoke_cmd(:eval, received)     # abs(x): what evaluation alone does
result    = invoke_cmd(:simplify, received) # evaluation, then simplify
```

Any command evaluates its arguments first, so `received` keeps the input only
until it is given to a command. `hold_cmd` holds a command and its arguments in
Julia, but its arguments are evaluated when the `HeldCmd` is built; pass a
quoted input to keep one unevaluated.

