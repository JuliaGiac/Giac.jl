# SymPy.jl Integration

Giac.jl provides integration with [SymPy.jl](https://github.com/JuliaPy/SymPy.jl) through bidirectional conversion functions, enabling interoperability between GIAC's symbolic computation engine and SymPy's Python-backed symbolic expressions.

The bridge is implemented as a package extension (`GiacSymPyExt`) that loads automatically when both `Giac` and `SymPy` are loaded.

## Basic Usage

```julia
using Giac, SymPy

# GiacExpr -> SymPy.Sym
@giac_var x
expr = x^2 + 1
sym_expr = to_sympy(expr)  # SymPy: x^2 + 1

# SymPy.Sym -> GiacExpr
x = symbols("x")
giac_expr = to_giac(sin(x) + log(x))  # GiacExpr: sin(x)+ln(x)

# Round-trip
original = giac_eval("sin(x) + ln(y)")
roundtrip = to_giac(to_sympy(original))  # mathematically equivalent
```

## GiacExpr to SymPy

The `to_sympy` function converts a `GiacExpr` to a `SymPy.Sym` using direct C++ Gen tree traversal (no string serialization), preserving symbolic structure.

### Numeric Types

```julia
to_sympy(giac_eval("42"))    # Sym(42)
to_sympy(giac_eval("3.14"))  # Sym(3.14)
to_sympy(giac_eval("3/4"))   # Sym(3) / Sym(4)
to_sympy(giac_eval("3+4*i")) # Sym(3) + Sym(4) * SymPy.IM
```

Arbitrary-precision integers (`ZINT`) are preserved as `BigInt`-backed SymPy integers:

```julia
to_sympy(giac_eval("123456789012345678901234567890"))
# == Sym(big"123456789012345678901234567890")
```

### Identifiers and Constants

```julia
to_sympy(giac_eval("x"))  # symbols("x")
to_sympy(giac_eval("pi")) # SymPy.PI
to_sympy(giac_eval("e"))  # SymPy.E
to_sympy(giac_eval("i"))  # SymPy.IM
```

!!! note
    GIAC evaluates bare `e` to `exp(1)` and `i` to the complex number `0+1*i` internally. These convert to `SymPy.E` and `SymPy.IM` respectively, matching SymPy's auto-simplification.

### Symbolic Expressions

```julia
to_sympy(giac_eval("sin(x)"))   # sin(symbols("x"))
to_sympy(giac_eval("cos(x)"))   # cos(symbols("x"))
to_sympy(giac_eval("exp(x)"))   # exp(symbols("x"))
to_sympy(giac_eval("sqrt(x)"))  # sqrt(symbols("x"))
to_sympy(giac_eval("ln(x)"))    # log(symbols("x"))

# log10: GIAC keeps log10(x) as the change-of-base form ln(x)/ln(10),
# preserved exactly as log(x)/log(10) (symbolic, no floating point).
to_sympy(giac_eval("log10(x)"))  # log(x)/log(10)

@giac_var x y
to_sympy(x + 1)    # symbols("x") + 1
to_sympy(x * y)    # symbols("x") * symbols("y")
to_sympy(x^2)      # symbols("x")^2
to_sympy(x - y)    # symbols("x") - symbols("y")
to_sympy(x / y)    # symbols("x") / symbols("y")
```

### Nested and Factored Expressions

```julia
to_sympy(giac_eval("sin(cos(tan(x)))"))
# sin(cos(tan(symbols("x"))))

@giac_var z
factored = Giac.Commands.factor(z^2 - 1)  # (z-1)*(z+1)
SymPy.expand(to_sympy(factored)) == symbols("z")^2 - 1  # true
```

## Name Mapping

GIAC and Julia/SymPy use different names for the natural logarithm; the bridge maps it automatically in both directions. Functions with identical names (`sin`, `cos`, `exp`, `sqrt`, `tan`, …) are resolved from `Base` (Giac → SymPy) or used directly by their SymPy class name (SymPy → Giac).

| GIAC | Julia / SymPy |
|------|---------------|
| `ln` | `log` |
| `log10` | `log(x)/log(10)` (change-of-base, kept symbolic) |
| `sin`, `cos`, `tan`, `exp`, `sqrt`, … | same name |

## SymPy to GiacExpr

The `to_giac` function converts a `SymPy.Sym` to a `GiacExpr` using direct C++ Gen construction (no string serialization). SymPy's internal representation is normalized back to GIAC idioms:

- `Pow(x, 1/2)` (SymPy's `sqrt(x)`) → GIAC `sqrt(x)`
- `Mul(x, Pow(y, -1))` (SymPy's `x/y`) → GIAC `x/y`
- `Add(x, Mul(-1, y))` (SymPy's `x - y`) → GIAC `x-y`
- SymPy singletons `Zero`, `One`, `NegativeOne`, `Half` → the corresponding GIAC literals / fraction
- SymPy constants → GIAC counterparts (`PI` → `pi`, `E` → `e`, `I` → `i`)

```julia
x = symbols("x"); y = symbols("y")
to_giac(Sym(42))            # 42
to_giac(Sym(3) // Sym(4))   # 3/4
to_giac(sin(x))             # sin(x)
to_giac(log(x))             # ln(x)   (reverse name mapping)
to_giac(sqrt(x))            # sqrt(x)
to_giac(x^2 + 2*x + 1)      # x^2+2*x+1
```

Arbitrary-precision integers are transferred via direct GMP binary access:

```julia
to_giac(Sym(big"123456789012345678901234567890"))
# GiacExpr holding a ZINT (arbitrary-precision integer)
```

## Round-Trip Fidelity

```julia
for s in ["42", "x", "sin(x)", "ln(x)", "sqrt(x)", "x+1",
          "x*y", "x^2", "3/4", "3+4*i", "pi", "sin(cos(tan(x)))"]
    original = giac_eval(s)
    @test to_giac(to_sympy(original)) == original
end
```

## Error Handling

Unsupported GIAC types throw an `ErrorException`:

```julia
to_sympy(giac_eval("\"hello\""))  # ERROR: Cannot convert GIAC string to SymPy.Sym
```

Non-scalar SymPy values (matrices) are refused by the scalar bridge:

```julia
x = symbols("x")
to_giac([x 1; 1 x])  # ERROR: to_giac(::AbstractArray{<:SymPy.Sym}) is not supported
```

## API Reference

See the [Conversion Functions](../api/core.md#conversion-functions) section in the Core API documentation for the full API reference of `to_sympy` and `to_giac`.