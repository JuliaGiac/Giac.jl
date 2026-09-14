# Nemo.jl Integration

Giac.jl provides a bidirectional bridge to [Nemo.jl](https://github.com/Nemocas/Nemo.jl) through two functions, enabling interoperability between GIAC's symbolic computation engine and Nemo's FLINT/Arb/Antic-backed algebraic types.

The bridge is implemented as a package extension (`GiacNemoExt`) that loads automatically when both `Giac` and `Nemo` are loaded.

## Why Nemo (not Oscar)

Oscar.jl builds on Nemo and adds groups, algebraic geometry, polyhedral geometry, etc. — domains with **no Giac analogue** (a `GiacExpr` cannot represent a permutation group or a scheme). The Nemo element types that matter for a Giac bridge (`ZZRingElem`, `QQFieldElem`, polynomials, finite-field and number-field elements, matrices) are exactly the ones Oscar re-exports from Nemo, so a Nemo bridge covers Oscar users too. Targeting Nemo keeps the install cheap (FLINT only) and CI-viable; Oscar pulls GAP + Singular + polymake and currently fails to precompile in some environments.

## The two entry points

```julia
using Giac, Nemo

# Nemo -> Giac   (the element carries its parent, so no extra argument)
to_giac(ZZ(42))                         # GiacExpr 42
to_giac(QQ(3, 4))                       # GiacExpr 3/4
R, x = polynomial_ring(ZZ, "x")
to_giac(3x^3 - 2x + 5)                  # GiacExpr 3*x^3-2*x+5

# Giac -> Nemo   (caller supplies the destination parent ring)
to_nemo(giac_eval("42"), ZZ)            # ZZRingElem 42
to_nemo(giac_eval("3/4"), QQ)           # QQFieldElem 3//4
to_nemo(giac_eval("x^2+1"), R)          # ZZPolyRingElem x^2+1
```

`to_nemo` takes a **parent ring** because Nemo elements are parent-typed (there is no free "Nemo integer", only `ZZ(42)`, `QQ(42)`, an element of a specific polynomial ring, …), whereas a `GiacExpr` is an untyped symbolic tree. The caller therefore states the destination:

```julia
to_nemo(giac_eval("x^2+1"), polynomial_ring(ZZ, "x")[1])   # ZZPolyRingElem
K, a = number_field((polynomial_ring(QQ, "x")[1])^2 - 2, "a")
to_nemo(giac_eval("a^2+3"), K)                             # AbsSimpleNumFieldElem
F, t = finite_field(7, 3, "t")
to_nemo(giac_eval("t^2+1"), F)                            # FqFieldElem
to_nemo(giac_eval("[[1,2],[3,4]]"), matrix_space(ZZ, 2, 2)) # ZZMatrix
```

## GiacExpr to Nemo (`to_nemo`)

| Target parent | Accepted Giac input | Result |
|---------------|----------------------|--------|
| `ZZ` | integer (`INT`/`ZINT`) | `ZZRingElem` |
| `QQ` | integer or rational (`INT`/`ZINT`/`FRAC`) | `QQFieldElem` |
| univariate `PolyRing` over `ZZ`/`QQ` | polynomial in one free variable | `*PolyRingElem` |
| `AbsSimpleNumField` | polynomial in the generator (one free var) | `AbsSimpleNumFieldElem` |
| `FqField` (prime or non-prime) | constant, or polynomial in the generator | `FqFieldElem` |
| `MatSpace` over `ZZ`/`QQ` | `GiacExpr` matrix (`[[…],[…]]`) | `*Matrix` |

Coefficients of the destination polynomial are converted recursively into the base ring (`to_nemo(coeff, base_ring(parent))`), so a polynomial over `QQ` accepts `1/2*y^2+3` directly.

## Nemo to GiacExpr (`to_giac`)

| Nemo type | Giac result |
|-----------|--------------|
| `ZZRingElem` | `INT` or `ZINT` (arbitrary precision preserved) |
| `QQFieldElem` | `FRAC` |
| `ZZPolyRingElem` / `QQPolyRingElem` | symbolic polynomial in the generator name |
| `FqFieldElem` | integer (prime field) or polynomial in the generator symbol (non-prime) |
| `AbsSimpleNumFieldElem` | polynomial in the generator symbol, **already reduced** mod the defining polynomial |
| `ZZMatrix` / `QQMatrix` | `GiacMatrix` of converted entries |

## Round-trip fidelity

Round trips are compared **by value**, never by `string`: Nemo polynomials are canonical (expanded, ring-sorted), so a Giac factored form `factor(x^2-1)` arrives in Nemo expanded as `x^2-1`, and the printed term order can differ. The variable **name** survives both crossings; the ordering does not.

```julia
for (elem, parent) in [(ZZ(42), ZZ), (QQ(3,4), QQ),
                       (3x^3-2x+5, polynomial_ring(ZZ,"x")[1])]
    @test to_nemo(to_giac(elem), parent) == elem
end
```

## Refusals (v1)

Both directions refuse everything that is not algebraic over the supported rings. Every refusal throws an `ErrorException` whose message names the supported set, so the caller learns the boundary from the error itself.

**Inward (`to_nemo`)** refuses:
- transcendental functions: `sin`, `cos`, `tan`, `exp`, `ln`, `sqrt`, `log10`, …
- the constants `pi` and `e` (transcendental, no element in an algebraic ring)
- real and complex values (`DOUBLE`, `REAL`, `CPLX`) — see *Reals* below
- a non-integer rational into `ZZ`
- multivariate polynomials (more than one free variable)

**Outward (`to_giac`)** refuses:
- real balls (`ArbFieldElem` / `RealFieldElem`)
- complex balls (`AcbFieldElem` / `ComplexFieldElem`)
- `PadicFieldElem` (p-adics have no Giac analogue)

### Why reals are refused

Neither direction may go through a printed decimal chosen by a printer: a Giac `REAL` prints at ambient precision, and an Arb ball has a mantissa *and a radius*. Injecting one as text silently loses precision with no diagnostic — exactly the trap the LibPARI bridge warns about. v1 refuses reals/complexes outright. A precision-explicit path (`to_nemo(e, ArbField(prec))` / `to_giac(ball)` via mantissa/exponent) may be added later as an **opt-in** API.

## Known limitations

- **Factored structure is not preserved** Giac → Nemo: `factor(x^2-1)` becomes `x^2-1` (expanded) in Nemo.
- **`GF(p^n)` extension degree** is not auto-inferred: the caller must pass the `FqField`. A `GiacExpr` does not carry the extension degree.
- **Number-field / finite-field embeddings** are one-way: a Nemo element reduced mod its defining polynomial loses the embedding information when round-tripped.
- **Multivariate polynomials** are not supported in v1.
- **Algebraic closure of QQ** (`algebraic_closure(QQ)` elements) and **Cauchy/real-complex balls** are refused (carry root indices / radii that Giac's flat `Gen` tree cannot faithfully represent).
- **Compat:** the bridge depends on Nemo 0.56 API surfaces (`AbsSimpleNumFieldElem`, `FqFieldElem`, `Nemo._coeff`, `Nemo.coeff`, `coefficients`, `defining_polynomial`, `matrix_space`). Nemo has historically renamed types between minor versions; the compat is pinned to `"0.56"` and should be re-validated on bumps.

## API Reference

See the [Conversion Functions](../api/core.md#conversion-functions) section in the Core API documentation for the full API reference of `to_giac` and `to_nemo`.