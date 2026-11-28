# OpenMath.jl: Giac ↔ OpenMath

With [OpenMath.jl](https://github.com/s-celles/OpenMath.jl) loaded, Giac
expressions convert to OpenMath objects and back, through the
[giac-openmath](https://github.com/JuliaGiac/giac-openmath) table: the
meaning of GIAC's expression-tree nodes in OpenMath Content Dictionaries.
OpenMath is a common language: a program that maps its own names to it once
can exchange expressions with Giac without a table of its own for Giac.

OpenMath.jl is not registered yet: install it from its repository.

```julia
using Pkg
Pkg.add(url = "https://github.com/s-celles/OpenMath.jl")
```

```julia
using Giac, OpenMath

to_openmath(giac_eval("ln(x) + 1/2"))
# OMA(OMS(arith1#plus), OMA(OMS(transc1#ln), OMV(x)), OMA(OMS(arith1#divide), OMI(1), OMI(2)))
# (in a sum, GIAC holds 1/2 as inv(2); a fraction on its own is nums1#rational(1, 2))

g = Giac.from_openmath(OMSymbol("calculus1", "defint")(
        OMSymbol("interval1", "interval")(OMInteger(0), OMInteger(1)),
        OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")],
                  OMSymbol("arith1", "power")(OMVariable("x"), OMInteger(2)))))
# 1/3: GIAC evaluates what it receives

Giac.giac_source(OMSymbol("arith1", "plus")(OMVariable("x"), OMInteger(1)))
# "(x) + (1)", the GIAC input, not evaluated
```

## The result and GIAC's messages

`from_openmath` has GIAC evaluate what it receives, and GIAC may say how it
computed it. [`evaluate_with_diagnostics`](@ref) keeps both:

```julia
o = OMApplication(OMSymbol("calculus1", "int")(
        OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")],
                  OMSymbol("arith1", "abs")(OMVariable("x")))), [OMVariable("x")])
r = evaluate_with_diagnostics(() -> Giac.from_openmath(o))
r.value         # 1/2*x^2*sign(x)
r.diagnostics   # :assumption, "integration of abs or sign assumes constant sign by
                #   intervals (correct if the argument is real)", and "Check [abs(x)]"
```

## What maps to what

The table decides, not this extension: it holds every GIAC node the
conversion knows, the OpenMath symbols they mean, and the GIAC input to write
from OpenMath. Its first version covers arith1, transc1, relation1, logic1,
nums1, rounding1, minmax1, complex1, integer1, calculus1 and limit1. A few
points worth knowing:

| GIAC | OpenMath |
|---|---|
| `ln(x)` (and `log(x)`, read as `ln`) | `transc1#ln(x)` |
| `logb(x, b)`, `log10(x)` | `transc1#log(b, x)`, the base first |
| `max(x, y)` | `minmax1#max(set1#set(x, y))` |
| `integrate(f, x)` | the antiderivative of `x -> f` (`calculus1#int`), applied to `x` |
| `integrate(f, x, a, b)` | `calculus1#defint(interval1#interval(a, b), x -> f)` |
| `limit(f, x, a, 1)` | `limit1#limit(a, limit1#above, x -> f)` |
| `+infinity` | `nums1#infinity` |
| fractions `p/q` | `nums1#rational(p, q)` |
| floats | `OMF` |

The table is embedded in the extension (`ext/giac_openmath_table.jl`, at a
commit of giac-openmath, checked by SHA-256); `test/update_openmath_table.jl`
updates it.

## Refusals

What the table does not list, or refuses, is an
`OpenMath.OpenMathConversionError`, with the table's reason when it has one,
rather than a guess:

- GIAC's `irem` and `iquo` round differently from `integer1#remainder` and
  `#quotient` for negative numbers;
- `x mod 3` is a residue class, not a remainder;
- bare `infinity` is unsigned in GIAC;
- lists, strings, programs, and any command without a Content Dictionary
  symbol (`gbasis`, `desolve`…).

From OpenMath, a variable named like a GIAC constant or command (`e`, `pi`,
`sin`…) is refused too, since GIAC would read it as that constant or
command; so is an antiderivative applied at another variable than its own.

An entry says that a GIAC node and an OpenMath symbol name the same operation
with the same arguments; that their domains and branch cuts agree has not been
checked, and the table's notes record what is known to differ.

## Checked against OpenMath.jl's Symbolics phrasebook

The tests write Symbolics expressions to OpenMath with OpenMath.jl's own
phrasebook, read them into GIAC with this one, and compare with Giac.jl's
Symbolics bridge; and the other way round. Two phrasebooks written apart agree
on the expressions tested.
