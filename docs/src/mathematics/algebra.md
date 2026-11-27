# Algebra

Giac.jl provides powerful symbolic algebra capabilities including polynomial factorization, expansion, simplification, equation solving, and polynomial arithmetic.

## Setup

```julia
using Giac
using Giac.Commands: factor, expand, simplify, solve, gcd, lcm, quo, rem

@giac_var x y
```

## Polynomial Factorization

### Factoring Polynomials

Factor polynomials into irreducible factors using the `factor` command:

```julia
factor(x^2 - 1)
# Output: (x-1)*(x+1)

factor(x^2 - 4)
# Output: (x-2)*(x+2)

factor(x^2 + 2*x + 1)
# Output: (x+1)^2
```

### Factoring Higher-Degree Polynomials

```julia
factor(x^3 - 1)
# Output: (x-1)*(x^2+x+1)

factor(x^4 - 1)
# Output: (x-1)*(x+1)*(x^2+1)
```

## Polynomial Expansion

### Expanding Products

Expand products and powers of polynomials using the `expand` command:

```julia
expand((x + 1)^2)
# Output: x^2+2*x+1

expand((x + 1)^3)
# Output: x^3+3*x^2+3*x+1

expand((x - 1) * (x + 1))
# Output: x^2-1
```

### Expanding More Complex Expressions

```julia
expand((x + 2) * (x - 3) * (x + 1))
# Expands to full polynomial form

expand((x + y)^2)
# Output: x^2+2*x*y+y^2
```

## Simplification

### Simplifying Rational Expressions

Simplify expressions using the `simplify` command:

```julia
simplify((x^2-1)/(x-1))
# Output: x+1

simplify((x^3-x)/(x^2-1))
# Output: x
```

### Simplifying Complex Expressions

```julia
simplify((x^2+2*x+1)/(x+1))
# Output: x+1
```

## Equation Solving

### Solving Polynomial Equations

Solve equations using the `solve` command:

```julia
solve(x^2 - 4, x)
# Output: [-2, 2]

solve(x^2 - 1, x)
# Output: [-1, 1]

solve(x^2 + 2*x + 1, x)
# Output: [-1]
```

### Solving Higher-Degree Equations

```julia
solve(x^3 - 1, x)
# Returns all roots including complex

solve(x^2 - 2, x)
# Output includes sqrt(2) and -sqrt(2)
```

## Equations as values

`a ~ b` is an equation, and it can be worked on like any other value. Its sides
are `lhs` and `rhs`; arithmetic with an equation applies to both sides;
`isolate` solves for one variable and gives the result as an equation; and an
equation can be the rule of a substitution.

```julia
@giac_var x y
eq = 2x + 3 ~ y
lhs(eq), rhs(eq)            # 2*x+3, y

eq - 3                      # 2*x = y-3
(eq - 3) / 2                # x = (y-3)/2, once simplified
eq + (x ~ 1)                # 3*x+3 = y+1

isolate(eq, x)              # x = (y-3)/2
isolate(x^2 ~ y, x)         # two equations, one per solution: x = ±√y

substitute(x + y, y ~ 2x)   # 3*x
substitute(y^2, isolate(eq, y))
```

`~` builds the equation without printing and parsing its sides, so a float
keeps all its digits: `x ~ 0.123456789012345`. Equations between arrays of
expressions, and solving for a matrix unknown, are described in
[Linear Algebra](linear_algebra.md#Matrix-equations).
## Collecting Terms
`collect_terms(e, vars)` writes `e` as a sum over the monomials in the variables
`vars`, each with its coefficient collected and normalized. Higher degrees come
first, then higher powers of the earlier variables. A factor that depends on the
variables without being a power of one (`sin(x1)`) is part of the monomial.
`Giac.coefficients(e, vars)` gives the pieces as a `Dict`, with the term free of
`vars` under `1`.
@giac_var x1 x2 a b
collect_terms(a*x1*x2 + b*x1*x2 + x2^2 + x1^2, [x1, x2])   # x1^2+(a+b)*x1*x2+x2^2
collect_terms(a*sin(x1)*x2 + b*sin(x1)*x2, [x1, x2])      # (a+b)*x2*sin(x1)
c = Giac.coefficients(a*x1^2 + b*x1*x2 + 2a*x1^2 + 3, [x1, x2])
c[x1^2]              # 3*a
c[one(GiacExpr)]     # 3
`coefficients` is not exported, as other algebra packages export a function of
that name.

## GCD and LCM

### Greatest Common Divisor

Find the GCD of polynomials using the `gcd` command:

```julia
gcd(x^2 - 1, x - 1)
# Output: x-1

gcd(x^2 - 4, x^2 - 4*x + 4)
# Output: x-2
```

### Least Common Multiple

Find the LCM of polynomials using the `lcm` command:

```julia
lcm(x - 1, x + 1)
# Output: (x-1)*(x+1) or equivalent

lcm(x^2, x^3)
# Output: x^3
```

## Polynomial Division

### Quotient

Compute the quotient of polynomial division using the `quo` command:

```julia
quo(x^3 - 1, x - 1)
# Output: x^2+x+1

quo(x^4, x^2)
# Output: x^2
```

### Remainder

Compute the remainder of polynomial division using the `rem` command:

```julia
rem(x^3, x - 1)
# Output: 1

rem(x^3 + x, x^2 + 1)
# Computes the polynomial remainder
```

### Quotient and Remainder Together

For polynomial division, the relationship `dividend = quotient * divisor + remainder` always holds:

```julia
# For x^3 - 1 divided by x - 1:
# quo(x^3 - 1, x - 1) = x^2 + x + 1
# rem(x^3 - 1, x - 1) = 0
# Verification: (x - 1) * (x^2 + x + 1) = x^3 - 1 ✓
```

## Systems of Equations

### Solving Linear Systems

Solve systems of equations by passing lists of equations and variables:

```julia
@giac_var x y

# System: x + y = 1, x - y = 0
solve([x + y ~ 1, x - y ~ 0], [x, y])
# Output: [[1/2, 1/2]]
```

### Solving Nonlinear Systems

```julia
# System: x^2 + y^2 = 1, x = y
solve([x^2 + y^2 ~ 1, x ~ y], [x, y])
# Returns solutions on the unit circle where x = y
```

## Notes

- All algebraic operations work symbolically, not numerically
- The `~` operator creates equations for use with `solve`
- For numerical solutions, convert results using `to_julia`
- `simplify` may not always produce the simplest form; try `normal` for rational simplification
- `factor` factors over the rationals by default; use `cfactor` for complex factorization
