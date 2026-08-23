# SymPy.jl Integration

Giac.jl provides integration with [SymPy.jl](https://github.com/JuliaPy/SymPy.jl) through the `to_sympy` conversion function, enabling interoperability between GIAC's symbolic computation engine and SymPy's Python-backed symbolic expressions.

The bridge is implemented as a package extension (`GiacSymPyExt`) that loads automatically when both `Giac` and `SymPy` are loaded.

## Basic Usage

```julia
using Giac, SymPy

# GiacExpr -> SymPy.Sym
@giac_var x
expr = x^2 + 1
sym_expr = to_sympy(expr)  # SymPy: x^2 + 1

# From a string
result = giac_eval("sin(x) + ln(y)")
to_sympy(result)  # sin(symbols("x")) + log(symbols("y"))
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

GIAC and Julia/SymPy use different names for the natural logarithm; the bridge maps it automatically. Functions with identical names (`sin`, `cos`, `exp`, `sqrt`, `tan`, …) are resolved from `Base` and applied to SymPy arguments.

| GIAC | Julia / SymPy |
|------|---------------|
| `ln` | `log` |
| `sin`, `cos`, `tan`, `exp`, `sqrt`, … | same name |

## Error Handling

Unsupported GIAC types throw an `ErrorException`:

```julia
to_sympy(giac_eval("\"hello\""))  # ERROR: Cannot convert GIAC string to SymPy.Sym
```

## API Reference

See the [Conversion Functions](../api/core.md#conversion-functions) section in the Core API documentation for the full API reference of `to_sympy`.