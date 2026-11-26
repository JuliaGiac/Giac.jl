## Quick Start

```julia
using Giac
using Giac.Commands: factor, expand, diff, integrate, limit, simplify, solve

# Basic evaluation through Giac
result = giac_eval("2 + 3")        # 5
factored = giac_eval("factor(x^2 - 1)")  # (x-1)*(x+1)

# Create symbolic variables
@giac_var x y

# Arithmetic
println(x + y)   # x+y
println(x * y)   # x*y
println(x ^ 2)   # x^2

# Evaluate expressions
expr = x^2 + 2*x*y + y^2

# Factor polynomials
result = factor(expr)  # Returns (x+y)^2

# Differentiate
derivative = diff(result, x)  # Returns 2*(x+y)

# Integrate
integral = integrate(x^2, x)  # Returns x^3/3

# Calculus using Giac.Commands
f = giac_eval("x^3")
# or using simpler syntax
f = x^3
df = diff(f, x)                    # 3*x^2
F = integrate(f, x)                # x^4/4
f = sin(x)/x  # or using more heavy syntax giac_eval("sin(x)/x")
lim = limit(f, x, 0)  # 1

# Algebra using Giac.Commands
factor(x^2 - 1)           # (x-1)*(x+1)
expand((x+1)^3)           # x^3+3*x^2+3*x+1
simplify((x^2-1)/(x-1))   # x+1
solve(x^2 - 4, x)         # list[-2,2]

# Equation syntax using ~ operator (Symbolics.jl convention)
eq = x^2 - 1 ~ 0                       # Creates equation: x^2-1=0
solve(eq, x)                           # Solves: [-1, 1]

# ~ works with mixed types
eq1 = x ~ 5                            # x=5
eq2 = 0 ~ x^2 - 4                      # 0=x^2-4

# Mixed-type arithmetic with Julia numbers
x - (1//2)                             # x-1/2 (Rational)
x + (1 + 2im)                          # x+1+2*i (Complex)
x + π                                  # x+pi (Irrational)
x * ℯ                                  # e*x (Euler's number)

# Decimals stay exact under @exact (0.1 alone is a binary float)
@exact 0.1 + 0.2                       # 3/10
@exact 0.5x^2 + 2π * x                 # 1/2*x^2+2*pi*x

# Or use invoke_cmd for any command
invoke_cmd(:factor, giac_eval("x^2 - 1"))  # (x-1)*(x+1)

# Convert to Julia types
to_julia(giac_eval("42"))    # 42::Int64
to_julia(giac_eval("3/4"))   # 3//4::Rational{Int64}
# or using |> operator
giac_eval("3/4") |> to_julia
```

To write decimals and keep them exact, see [Exact Numbers](@ref) and [`@exact`](@ref).
