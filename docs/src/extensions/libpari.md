# LibPARI.jl Integration

Giac.jl can exchange values with [LibPARI.jl](https://github.com/s-celles/LibPARI.jl),
a Julia wrapper for the [PARI/GP](https://pari.math.u-bordeaux.fr/) computer
algebra system. The bridge is an optional package extension: it becomes
available as soon as both packages are loaded, and costs nothing otherwise.

```julia
using Giac, LibPARI

to_giac(gp_eval("(w+x)^2"))     # PARI  -> Giac
pari(giac_eval("x^2+1"))        # Giac  -> PARI
```

The bridge lives here, in Giac.jl, rather than in LibPARI.jl. Hosting a bridge
means paying its CI cost, and `PARI_jll` (19 MB, ~13 Julia dependencies) is far
cheaper for Giac.jl to pull than `GIAC_jll` (73 MB, ~56 dependencies) would be
for LibPARI.jl.

## Installation

```julia
using Pkg
Pkg.add("Giac")
Pkg.add("LibPARI")   # 0.17 or later
```

`LibPARI` is a weak dependency of Giac.jl, so nothing is installed until you
ask for it. The extension loads automatically when both packages are in scope.

## The two entry points

There is exactly one function per direction, following the convention
LibPARI's own Symbolics.jl bridge established.

| Direction | Call | Owner of the name |
|---|---|---|
| PARI → Giac | `to_giac(g::LibPARI.Gen)` | Giac.jl |
| Giac → PARI | `LibPARI.pari(e::GiacExpr)` | LibPARI.jl |

The inward direction adds a method to LibPARI's own entry point rather than
introducing a second name such as `to_pari`. That is not type piracy: LibPARI
owns `pari`, Giac owns `GiacExpr`. One entry point, one contract.

## The contract

**The bridge is value-preserving and name-preserving. It is not
representation-preserving.**

A PARI polynomial carries a variable *number* whose *priority* is
process-global. `varhigher` and `varlower` change that ordering for the whole
process, so `(w+x)^2` prints as `x^2+2*w*x+w^2` or as `w^2+2*x*w+x^2`
depending on which ordering is in force. Giac orders by its own rules. The
variable *name* survives both crossings; the ordering does not.

Consequently:

* Compare round trips **by value**: `pari(to_giac(g)) == g`. On a `Gen`, `==`
  is PARI's `gequal`.
* **Never** compare by text: `string(x) == string(y)` is an assertion that
  will be red or flaky, and the test suite contains no such comparison.

```julia
using Giac, LibPARI

g = gp_eval("(w+x)^2")
pari(to_giac(g)) == g        # true — this is the assertion to make
string(pari(to_giac(g))) == string(g)   # do not rely on this
```

## Mapping table

Both systems expose a runtime type tag — `LibPARI.gentype(g)` returns a
`LibPARI.PariType`, `Giac.giac_type(e)` returns a `Giac.GenTypes.T`. The
table below drives the implementation.

### PARI → Giac (`to_giac`)

| PARI tag | Giac tag | Route | Notes |
|---|---|---|---|
| `T_INT` | `INT` / `ZINT` | via `BigInt` | Giac picks the width |
| `T_FRAC` | `FRAC` | via `Rational{BigInt}` | |
| `T_REAL` | `REAL` / `DOUBLE` | via `BigFloat` | Giac picks the width by how much precision the value needs |
| `T_COMPLEX` | `CPLX` | recurse on `real`/`imag` | |
| `T_POL` | `SYMB` / `IDNT` / scalar | Horner over `gpolvar` | a degree-0 `t_POL` collapses to its constant, which is what PARI's own `==` compares it to |
| `T_VEC` | `VECT` | elementwise | |
| `T_COL` | `VECT` | elementwise | **widens** — see limitations |
| `T_VECSMALL` | `VECT` | elementwise | **widens** |
| `T_LIST` | `VECT` | elementwise | **widens** |
| `T_MAT` | `VECT` of `VECT`, row-major | elementwise | `size(g)` reports Julia's `(rows, columns)`; PARI stores columns |
| anything else | — | **refused, tag named** | |

### Giac → PARI (`LibPARI.pari`)

| Giac tag | PARI tag | Route | Notes |
|---|---|---|---|
| `INT` | `T_INT` | via `Int64` | |
| `ZINT` | `T_INT` | via `BigInt` | |
| `FRAC` | `T_FRAC` / `T_INT` | `numer`/`denom`, recursively | also covers Giac's habit of storing a complex number with rational parts as a `FRAC`, e.g. `(3+2*i)/4` |
| `DOUBLE` | `T_REAL` | via `Float64` | PARI has no hardware-float tag |
| `REAL` | `T_REAL` | via `BigFloat` | see [Reals and precision](@ref) |
| `CPLX` | `T_COMPLEX` | recurse on real/imaginary part | |
| `IDNT` | `T_POL` | the free symbol of that name | Giac constants such as `pi` are **refused** |
| `SYMB` | `T_POL` | `symb2poly` + Horner | only when the expression is a polynomial in its free identifiers |
| `VECT` (flat) | `T_VEC` | elementwise | |
| `VECT` of equal-length `VECT`s | `T_MAT` | column by column | |
| anything else | — | **refused, tag named** | |

## What is refused, and why

Every refusal raises an `ArgumentError` that **names the tag** it could not
translate, so the message is actionable on its own.

```julia
julia> to_giac(gp_eval("3+O(5^4)"))
ERROR: ArgumentError: to_giac: no Giac counterpart for the PARI tag T_PADIC;
the bridge covers T_INT, T_FRAC, T_REAL, T_COMPLEX, T_POL, T_VEC, T_COL,
T_VECSMALL, T_LIST and T_MAT

julia> pari(giac_eval("sin(x)"))
ERROR: ArgumentError: pari: no PARI counterpart for the Giac tag SYMB
(`sin(x)` is not a polynomial in identifiers — Giac reports `sin(x)` as one of
its variables); the bridge covers INT, ZINT, FRAC, DOUBLE, REAL, CPLX, IDNT,
SYMB and VECT
```

| Refused | Direction | Reason |
|---|---|---|
| `T_INTMOD` / `MOD` | both | Giac's `MOD` is opaque to the public API: `op`, `left`, `right` and `feuille` all return the `MOD` itself, so the residue and the modulus cannot be recovered and the value could not come back. Giac also normalises to a symmetric representative — `5 % 7` becomes `-2 % 7` — so even the value is not stable. |
| `T_STR` / `STRNG` | both | LibPARI exposes no accessor for the characters of a `t_STR` in its public API — `string(g)` returns the GP literal, quotes and escapes included, and reading the value back out of it is the text round trip this contract forbids. Giac's side is fine (`to_julia` on a `STRNG` returns the characters), but one working side is not enough for a round trip, and strings carry no mathematical content for a CAS bridge. If LibPARI gains a public accessor, this row can move to the supported table. |
| `T_RFRAC`, and any Giac `SYMB` that is a rational function | both | PARI represents `1/(x+1)` as a `t_RFRAC`; the bridge covers polynomials only. `1/x` and `x/(x+1)` are detected through Giac's `denom`. |
| `T_PADIC`, `T_QUAD`, `T_SER`, `T_POLMOD`, `T_CLOSURE`, … | outward | No Giac counterpart. |
| Giac `SYMB` involving `sin`, `exp`, `sqrt`, … | inward | Not a polynomial. Giac's `lvar` reports each such subexpression as a generalised variable rather than as an identifier, which is exactly the test the bridge applies. |
| Giac `IDNT` that is a constant (`pi`, `i`, …) | inward | A PARI variable named `pi` is not Giac's π, and inventing one would be wrong. |
| A ragged or mixed Giac `VECT` | inward | PARI has no ragged container. Only a rectangular nesting maps onto a `t_MAT`. |
| Giac `POLY`, `FUNC`, `MAP`, … | inward | No PARI counterpart. |

## Reals and precision

Precision is a scope. `setprecision(LibPARI.Gen, bits) do … end` sets
LibPARI's working precision in bits, and it governs PARI *computations*.

**The bridge does not consult it.** A real crosses carrying the precision of
the value itself, in both directions — a 512-bit `t_REAL` reaches Giac with
all 512 bits even while the ambient setting is 64, and comes back a 512-bit
`t_REAL`.

!!! note "Windows, on GIAC_jll before v2.0.2"
    Reals did not cross on Windows at all under `GIAC_jll` v2.0.1 with
    `libgiac_julia_jll` v0.5.0: a binary ABI mismatch made the wrapper read a
    `_REAL` tag as `_DOUBLE_`, and a real arrived truncated to twelve
    significant digits. Giac.jl's `[compat]` bounds now exclude that pair, so
    what follows holds on every platform. See
    [Reals once did not cross on Windows](@ref) for the diagnosis.

```julia
using Giac, LibPARI

wide = setprecision(() -> LibPARI.PARI.mppi(), LibPARI.Gen, 512)
precision(wide)                                   # 512

setprecision(LibPARI.Gen, 64) do
    pari(to_giac(wide)) == wide                   # true
end
precision(pari(to_giac(wide)))                    # 512
```

### Why the bridge never routes a value through text

Injecting a PARI real into GP as a decimal string turns a 512-bit real into a
128-bit one, silently, because PARI prints at the current `realprecision`:

```julia
p = setprecision(() -> LibPARI.PARI.mppi(), LibPARI.Gen, 512)
precision(p)                             # 512
precision(gp_eval(string(p)))            # 128  — no error, no warning
```

Values therefore cross structurally, or through exact Julia values (`BigInt`,
`Rational`, `BigFloat`) — never through `string`. `BigFloat(::Gen)` widens the
working precision to hold the mantissa exactly, and `LibPARI.pari(::BigFloat)`
rebuilds a `t_REAL` from the mantissa and exponent, so the PARI legs are exact
by construction.

### The one place text is unavoidable

Reading a Giac `REAL` back out is the exception, and it is worth stating
plainly. The libgiac wrapper exposes `to_double` — a `Float64`, and therefore
lossy — and nothing for an MPFR value; reaching past it into an undeclared
libgiac C symbol is a call this project does not make. Giac's printer emits a
`REAL` at that value's *own* precision rather than at the global `Digits`
setting, so the decimal it produces is faithful and only the bit width has to
be recovered.

The bridge recovers that width by search and then re-encodes the candidate,
accepting it only when the printed forms agree character for character. A
width for which nothing agrees raises rather than returning a quietly-rounded
value. The behaviour is pinned by tests at 64, 128, 192, 256, 384, 512 and
1024 bits.

Note precisely what that check does and does not establish. It tests the
**printer's self-consistency**, not its fidelity to the stored value. Those
coincide only where the printer is faithful — a distinction that was not
academic: under the old Windows ABI mismatch the check confirmed a truncated
answer without complaint. See
[Reals once did not cross on Windows](@ref).

This would become unnecessary if the wrapper gained an MPFR accessor for
`REAL`; until then it is the bridge's only text-mediated step.

## Reals once did not cross on Windows

!!! compat "Fixed — kept as history"
    Giac.jl requires `GIAC_jll` v2.0.2 and `libgiac_julia_jll` v0.5.1, which
    do not have the defect described here. The section is kept because the
    diagnosis is worth having on record, and because it still applies if you
    are pinned to older binaries.

Under `GIAC_jll` v2.0.1 with `libgiac_julia_jll` v0.5.0, a `t_REAL` did not
survive the crossing on Windows. Every real arrived truncated to twelve
significant digits, whatever precision was asked for:

```julia
p = setprecision(() -> LibPARI.PARI.mppi(), LibPARI.Gen, 512)

pari(to_giac(p)) == p     # was false on Windows, true elsewhere
# expected  3.1415926535897932384626433832795028842
# obtained  3.14159265359 0000062
```

This was **not** a Giac printing quirk, and not something the bridge could
work around. It was an ABI bug between the two binaries.

`class gen` stored its tag as a bitfield —
`unsigned char type:5; unsigned char type_unused:3;`. GCC fuses adjacent
bitfield writes into one wider store and chooses the bit placement in a
version-dependent way. `GIAC_jll` was built with GCC 8 and
`libgiac_julia_jll` with GCC 10, so the two disagreed about which bits held
`type`: libgiac wrote a gen tagged `_REAL`, and the wrapper read back
`_DOUBLE_`. Giac.jl then believed it was holding a `Float64`, printed it at
the global `Digits` — default 12 — and the extra precision was gone.

That the loss was identical at 64, 128, 256, 512 and 1024 bits is the tell:
53 bits is all a mis-tagged `DOUBLE` ever had. **Raising `Digits` changed
nothing** — the precision was lost at the tag, not at the printer.

The fix was [JuliaPackaging/Yggdrasil#13717](https://github.com/JuliaPackaging/Yggdrasil/pull/13717),
which bumped `GIAC_jll` to v2.0.2 built with `GIAC_TYPE_ON_8BITS=1` — `type`
is a plain byte at offset 0, a layout no compiler can rearrange — and aligned
its `preferred_gcc_version` with the wrapper's, followed by
[Yggdrasil#14478](https://github.com/JuliaPackaging/Yggdrasil/pull/14478)
rebuilding `libgiac_julia_jll` as v0.5.1 against it. v0.5.0 was capped to
`GIAC_jll` 2.0.1 in the General registry, so the resolver cannot pair the old
wrapper with the new library. Same root cause as
[Giac.jl#22](https://github.com/JuliaGiac/Giac.jl/pull/22) and the diagnostic
probe in [Giac.jl#26](https://github.com/JuliaGiac/Giac.jl/pull/26).

**Everything else in the bridge worked on Windows throughout** — integers,
rationals, complex numbers, polynomials, vectors, matrices, the refusal list,
variable names. Only reals were affected, and a `DOUBLE` crossed correctly,
since a `DOUBLE` is what the mis-tag claimed it already was. On old binaries,
converting to an exact type first — `Rational` — crosses faithfully on every
platform.

The affected assertions were marked `@test_broken` on Windows rather than
skipped, precisely so that landing the two JLLs would surface them as
*unexpected passes*. They are now plain `@test`, unqualified on every
platform, which is what keeps the fix from silently regressing.

### What this said about the bridge's own safety check

The bridge reads a Giac `REAL` back by decoding its printed decimal, and
verifies the result by re-encoding it and comparing printed forms. On the
affected Windows builds that check was **blind**: re-encoding the truncated
value also printed twelve digits, the forms agreed, and a wrong answer was
confirmed without complaint.

The check establishes the printer's *self-consistency*, not its *fidelity to
the stored value*. Those coincide only where the tag is right. A guard worth
having, but not one that can detect a lie told further down the stack.

## Known limitations

Each of these is pinned by a test, so a change in behaviour shows up in
Giac.jl's suite rather than in your results.

1. **`T_COL`, `T_VECSMALL` and `T_LIST` widen to `T_VEC`.** Giac has a single
   vector type, so the container tag cannot survive. The elements do.

   ```julia
   g = gp_eval("[1,2,3]~")           # a t_COL
   back = pari(to_giac(g))
   back == gp_eval("[1,2,3]")        # true  — values preserved
   LibPARI.gentype(back)             # T_VEC — tag not preserved
   back == g                         # false
   ```

   If you need the round trip to be tag-exact, normalise on the PARI side
   first with `Vec(...)`.

2. **PARI's variable ordering does not cross**, as described under
   [The contract](@ref). Compare by value.

3. **Float tags are not preserved.** Giac's `DOUBLE` and `REAL` both land on
   PARI's `t_REAL`; coming back, Giac picks `DOUBLE` or `REAL` according to
   how much precision the value needs. Values are preserved either way.

4. **Reals cross on every platform**, including Windows, from `GIAC_jll`
   v2.0.2 and `libgiac_julia_jll` v0.5.1 — the versions Giac.jl's `[compat]`
   requires. On older binaries a `t_REAL` arrived on Windows truncated to
   twelve significant digits; see
   [Reals once did not cross on Windows](@ref).

5. **A `Gen` is not a `Number`.** It is a `LibPARI.PariObject`. Generic
   numeric code bounded by `T<:Number` will not accept one, and `Number`
   methods must not be assumed to apply.

6. **`LibPARI.PARI.gpolvar` takes a keyword**, not a positional argument:
   `gpolvar(; x1 = g)`. Most of LibPARI's generated bindings pass the first
   argument positionally and the rest as keywords; check the signature before
   calling one.

7. **`gp_eval` does not honour `setprecision(LibPARI.Gen, …)`.** It goes
   through the GP interpreter, which reads PARI's process-global
   `realprecision`, so `setprecision(() -> gp_eval("Pi"), LibPARI.Gen, 512)`
   returns a 128-bit value. This is documented, intended LibPARI behaviour —
   its `setprecision` docstring states that the scope "does not reach into
   the GP interpreter" — and it is worth repeating here because it is easy to
   trip over when building a test corpus. Call the binding directly,
   `LibPARI.PARI.mppi()`, when you want the scoped precision to apply. The
   bridge itself is unaffected: it never asks for a precision other than the
   value's own.

## API

Both methods live in the extension module, so their docstrings are available
once `LibPARI` is loaded:

```julia
using Giac, LibPARI

?to_giac          # includes the method for LibPARI.Gen
?LibPARI.pari     # includes the method for GiacExpr
```
