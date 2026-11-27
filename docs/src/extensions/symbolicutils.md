# SymbolicUtils.jl: exact conversion

With [SymbolicUtils.jl](https://github.com/JuliaSymbolics/SymbolicUtils.jl)
loaded (Symbolics is not needed), `to_symbolicutils` and `to_giac` convert
between Giac and SymbolicUtils **exactly**: numbers stay integers and
rationals, radicals and constants stay unevaluated terms, and anything without
an exact form is an error rather than a float. It was written for
[MathInterchange](https://github.com/MathInterchange)'s adapter, whose Lean
checkers read SymbolicUtils terms.

```julia
using Giac, SymbolicUtils
using Giac.Commands: integrate, simplify
@syms x::Real
@giac_var v
names = Dict("v" => x)                       # Giac name => SymbolicUtils symbol

to_symbolicutils(integrate(v^2 + 2, v); symbols = names)   # (1//3)*x^3 + 2x
to_symbolicutils(sqrt(giac_eval("2")) * v; symbols = names) # sqrt(2)*x, never 1.414…*x
to_symbolicutils(assuming(() -> simplify(sqrt(v^2)), v > 0); symbols = names)   # x

to_giac((0 < x) & (x <= 10); names = Dict(x => "v"))       # (v>0) and (10>=v)
```

## From Giac

| Giac | SymbolicUtils |
|---|---|
| integers | `Int`, or `BigInt` when it does not fit |
| fractions, `inv(n)` | `Rational{BigInt}` (`1//2`) |
| `t^(1/2)` | `sqrt(t)`, a term; `sqrt(2)` is never evaluated |
| other rational powers | `t^(p//q)`, unevaluated on a number |
| `pi` | `π` inside a term, so that `2π` is not folded into a float |
| `exp(1)` | the term `exp(1)` |
| `i` | `im` |
| `abs`, `exp`, `log`, `sin`, …, `atan`, `sinh`, … | terms on symbolic arguments |

`symbols` maps Giac names to the SymbolicUtils symbols to use (for instance
your own fresh names). A name not in it becomes a `Real` symbol of the same
name; with `strict_symbols = true` it is an `ArgumentError` instead, for a
caller to whom an identifier outside its request means something unexpected
came back. With `exact = true`, the default, a GIAC float or a function outside the
elementary ones (such as `Gamma`) is an `ArgumentError`; `exact = false`
accepts them.

## To Giac

`to_giac(t; names, exact = true)` builds the Giac expression node by node.
`names` maps SymbolicUtils symbols to Giac names. Comparisons become Giac
relations, and `&` and `|` become `and` and `or`. In exact mode a float (`0.5`)
or an unknown function is an `ArgumentError`.

A round trip keeps exactness:
`to_symbolicutils(to_giac(e; names); symbols)` is `e` for
`e = (1//3)*x^3 + sqrt(2)*x`.
