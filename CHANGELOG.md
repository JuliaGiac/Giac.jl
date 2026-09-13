# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.3] - 2026-08-07

### Changed

- **`GiacLibPARIExt` accepts LibPARI 0.18** — compat widened from `"0.17"`
  to `"0.17, 0.18"`. LibPARI 0.18.0 changed nothing in its core API: it
  narrows *its own* optional Symbolics bridge to Symbolics 7, which Giac.jl
  already requires (`Symbolics = "7"`). Without this, installing Giac.jl
  alongside LibPARI holds the latter back at 0.17.

- **`ModelContextProtocol` compat widened from `"0.4"` to `"0.4, 0.6"`**
  ([#60](https://github.com/s-celles/Giac.jl/pull/60),
  [#61](https://github.com/s-celles/Giac.jl/pull/61)). 0.5 is skipped
  deliberately, matching upstream. This PR was initially blocked: forcing
  MCP to its latest compatible version left `LibPARI` unresolvable, since
  the registered LibPARI 0.18.0 still capped its own MCP compat at `"0.4"`.
  Unblocked by releasing
  [LibPARI.jl 0.18.1](https://github.com/s-celles/LibPARI.jl/releases/tag/v0.18.1),
  which widens that bound the same way.

- **The macOS CI jobs run natively on `aarch64`** instead of asking for `x64`.
  `macos-latest` is Apple Silicon; `setup-julia` v2 tolerated the mismatch,
  but v3 rejects it outright (*"x64 arch has been requested on a macOS runner
  that has an arm64 (Apple Silicon) architecture"*), which is why
  [#52](https://github.com/s-celles/Giac.jl/pull/52) fails on macOS. All four
  binary dependencies — `GIAC_jll`, `libgiac_julia_jll`,
  `libcxxwrap_julia_jll` and `PARI_jll` — ship an `aarch64-apple-darwin`
  build, so nothing is lost by moving. Expressed as `exclude`/`include` rather
  than by dropping the `arch` matrix dimension, so only the two macOS check
  names change.

### Fixed

- **The docs build no longer warns about `api/core.md`'s HTML output size**
  (103.68 KiB against a 100 KiB soft threshold). The page legitimately carries
  the full core-API docstring set plus worked examples; `docs/make.jl` now
  lists it in `size_threshold_ignore`, Documenter's own recommended
  alternative to raising the general limit. The `missing_docs` warning for
  the ~2000 auto-generated `Giac.Commands` functions stays in `warnonly` by
  design — `commands_submodule.md` documents their usage pattern rather than
  each function individually, and `checkdocs_ignored_modules` was tried and
  rejected: it drops the whole submodule from Documenter's known bindings,
  breaking the `@ref`s that already resolve for `invoke_cmd`, `hold_cmd`,
  `release` and `Giac.Commands` itself.

- **The documentation is no longer deployed twice on every push to `main`.**
  Both `documentation.yml` and `CI.yml`'s `docs` job built the docs *and*
  pushed to `gh-pages`, so the two raced; the merge of
  [#58](https://github.com/s-celles/Giac.jl/pull/58) is where one lost, with
  `error: failed to push some refs`. Earlier pushes passed on luck, not
  correctness — the published docs were never wrong, only the CI colour was.
  The `docs` job is removed and the dedicated workflow kept, since it also
  covers tags (`tags: '*'`), which Documenter needs for versioned
  deployments. Its job is renamed to `Documentation` because the `Protect
  main` ruleset requires a status check under that exact name: without the
  rename, every pull request would wait forever on a check no workflow
  produced.

- **The LibPARI bridge's real-number tests no longer fail the suite on
  Windows**, and the platform difference behind them is documented rather than
  hidden. `main` was red on both Windows runners with 23 failures, all of them
  in `test_libpari_ext.jl`, all in reals.

  The cause is not Giac and not the bridge: it is a known ABI bug between the
  two binaries. `class gen` stored its tag as a bitfield, GCC fuses adjacent
  bitfield writes with version-dependent bit placement, and `GIAC_jll` is
  built with GCC 8 against `libgiac_julia_jll`'s GCC 10 — so libgiac writes a
  gen tagged `_REAL` and the wrapper reads back `_DOUBLE_`. The suite observes
  it directly: `Giac.giac_type(wide) == REAL` evaluates to `DOUBLE == REAL`.

  Everything else follows. Giac.jl believes it holds a `Float64`, prints at
  the global `Digits` — default 12 — and every real crosses truncated to
  twelve significant digits, identically at 64, 128, 256, 512 and 1024 bits,
  because 53 bits is all a mis-tagged `DOUBLE` ever had. Raising `Digits`
  would change nothing: the precision is lost at the tag, not at the printer.

  Fix in flight upstream:
  [Yggdrasil#13717](https://github.com/JuliaPackaging/Yggdrasil/pull/13717)
  bumps `GIAC_jll` to v2.0.2 with `GIAC_TYPE_ON_8BITS=1`, making the ABI
  compiler-invariant, followed by a `libgiac_julia_jll` bump. Same root cause
  as [#22](https://github.com/s-celles/Giac.jl/pull/22) and the probe in
  [#26](https://github.com/s-celles/Giac.jl/pull/26).

  One thing this did establish about the bridge itself: its decode *verifies
  itself* by re-encoding the candidate and comparing printed forms, and that
  check is blind here. Re-encoding the truncated value also prints twelve
  digits, the forms agree, and a wrong answer is confirmed. The check
  establishes the printer's self-consistency, not its fidelity — the two
  coincide only where the tag is right.

  The affected assertions are now marked `@test_broken` on Windows rather than
  skipped, so that when the two JLLs land the suite reports *unexpected
  passes* and tells whoever did it to delete the markers. Everything else
  in the bridge passes on Windows: integers, rationals, complex numbers,
  polynomials, vectors, matrices, refusals, variable names, the PARI stack
  check and the piracy check. A `DOUBLE`, needing no more than twelve digits,
  crosses correctly.

  The documentation said Giac's printer emits a `REAL` at the value's own
  precision "rather than at a global setting", presented as a measured fact.
  It was measured on Linux only. Corrected, with a dedicated section and a
  warning admonition on the reals section.

### Added

- **Dependabot for the pinned GitHub Actions** (`.github/dependabot.yml`),
  completing the automation added alongside CompatHelper. CompatHelper watches
  Julia dependencies and never looks at workflows, so nothing tracked the
  actions themselves — four of the eight pinned were one to three majors
  behind when this was written: `actions/checkout` v4 → v7.0.1,
  `codecov/codecov-action` v4 → v7.0.0, `julia-actions/setup-julia` v2 →
  v3.0.2, `julia-actions/cache` v2 → v3.2.0. Configured for one PR per action
  rather than a combined bump, so a failure is attributable to the action that
  caused it.

  This required one line in `.gitignore`. That file ignores everything by
  default (`*`) and allows files back a pattern at a time; the allowlist
  covered `.github/workflows/*.yml`, which does not reach the root of
  `.github/`, and GitHub requires the Dependabot config at exactly
  `.github/dependabot.yml`. The added line is a single negation for that one
  path — no other file changes status.

- **CompatHelper** and a **downgrade CI job**, closing two gaps in the
  repository's automation.

  `CompatHelper` opens a PR when a dependency's newest release falls outside
  this package's `[compat]` ceiling. LibPARI.jl already ran it; Giac.jl did
  not, despite having far more to watch. It would have caught a live problem:
  `ModelContextProtocol` was pinned to `"0.4"` while 0.6.1 was current, so
  `Pkg.add(Giac)` silently downgraded a user's MCP by two breaking minors.
  Configured with `subdirs = ["", "docs"]` so `docs/Project.toml` is covered
  too.

  `CI-Downgrade.yml` resolves the hard `[deps]` to the lowest versions
  `[compat]` claims to support and runs the suite there, on Julia 1.10 — the
  floor Julia, since some floors are not installable on newer versions. It is
  the complement to CompatHelper, which only ever raises ceilings: nothing
  else in CI tests the floors, because the main matrix always resolves to the
  newest compatible versions.

  The job deliberately skips the weak dependencies. A weakdep floor is a
  *pairwise* promise, but `Pkg.test` resolves the whole test target at once
  and would force all five weakdeps to their floors simultaneously — a
  combination that is unsatisfiable and that no user encounters, since one
  loads a single extension rather than five floor-pinned ones together.

- **`GiacTermInterfaceExt` now implements `head` and `children`**, completing
  the TermInterface protocol. TermInterface's `iscall` docstring makes them
  mandatory — *"If `iscall(x)` is true, then also `isexpr(x)` must be true.
  […] This means that, `head(x)` and `children(x)` must be defined. Together
  with `operation(x)` and `arguments(x)."* — but the extension defined only
  `iscall`/`isexpr`/`operation`/`arguments`/`maketerm`, so a consumer written
  against the protocol's documented spelling hit a `MethodError` exactly where
  `operation`/`arguments` would have answered.

  Giac is a language in which every expression node is a function call, so the
  two spellings coincide: `head` is `operation` and `children` is `arguments`.
  `sorted_children` needs no method — TermInterface defaults it to `children`,
  and Giac stores its arguments in order. On a leaf, where `isexpr` is false
  and the protocol requires nothing, `head`/`children` raise the same
  `ArgumentError` that `operation`/`arguments` raise rather than inventing a
  head for a node that has none. Closes
  [#41](https://github.com/s-celles/Giac.jl/issues/41).

- **A documentation page for the TermInterface extension**
  (`docs/src/extensions/terminterface.md`), which the extension previously
  lacked. It documents the protocol table and calls out a trap for anyone
  writing a traversal: a Giac numeric literal is a `GiacExpr`, **not** a
  `Number` — `giac_eval("42") isa Number` is `false`, and `to_julia` is what
  unwraps it — so a walk over `Number` / symbol / call looks exhaustive while
  silently dropping every literal. Dispatch on `isexpr` instead. The same
  shape caught SymbolicUtils.jl
  ([JuliaSymbolics/SymbolicUtils.jl#1024](https://github.com/JuliaSymbolics/SymbolicUtils.jl/issues/1024)).
  The caveat is repeated in the extension module's own header comment.

- **LibPARI.jl bridge**: values can now cross between Giac and
  [PARI/GP](https://pari.math.u-bordeaux.fr/) through a new weak-dependency
  package extension `GiacLibPARIExt` on
  [`LibPARI.jl`](https://github.com/s-celles/LibPARI.jl) 0.17. Two entry
  points, one per direction: `to_giac(g::LibPARI.Gen)` outward and a method
  on LibPARI's own `pari(e::GiacExpr)` inward — no second inward name. The
  bridge is hosted here rather than in LibPARI.jl because hosting means
  paying the CI cost, and `PARI_jll` (19 MB, ~13 dependencies) is far cheaper
  for Giac.jl to pull than `GIAC_jll` (73 MB, ~56 dependencies) would be the
  other way round.

  The bridge is **value-preserving and name-preserving, not
  representation-preserving**: PARI's variable priority is process-global and
  Giac orders by its own rules, so round trips are compared with `==` (PARI's
  `gequal`) and never with `string`. It covers `T_INT`, `T_FRAC`, `T_REAL`,
  `T_COMPLEX`, `T_POL`, `T_VEC`, `T_COL`, `T_VECSMALL`, `T_LIST` and `T_MAT`
  outward, and `INT`, `ZINT`, `FRAC`, `DOUBLE`, `REAL`, `CPLX`, `IDNT`,
  polynomial `SYMB` and `VECT` inward. Everything else is refused with an
  `ArgumentError` that names the tag it could not translate.

  Reals cross carrying the *value's* own precision rather than the ambient
  `setprecision(LibPARI.Gen, …)` setting, and never through a printed decimal
  — injecting a PARI real into GP as text silently truncates a 512-bit value
  to 128 bits. Known limitations (`T_COL`/`T_VECSMALL`/`T_LIST` widening to
  `T_VEC`, float tags not surviving, `MOD` and string types refused) are
  documented in `docs/src/extensions/libpari.md` and each is pinned by a test.

  The bridge has a dedicated CI job that runs its tests against a project
  containing only Giac and LibPARI, so a bridge failure is attributable and
  an accidental dependence on another extension would be caught.

### Fixed

- **Two `[compat]` lower bounds were unsatisfiable**, found by the new
  downgrade job on its first run:

  - `GIAC_jll = "2"` claimed support for 2.0.0, but `libgiac_julia_jll` 0.5
    requires `GIAC_jll >= 2.0.1`, so that floor could never resolve. Now
    `"2.0.1"`.
  - `CxxWrap = "0.16, 0.17"` claimed support for 0.16, but CxxWrap 0.16
    requires `libcxxwrap_julia_jll` 0.13 while this package pins 0.14.9, so
    0.16 could never resolve either. Now `"0.17"`.

  Neither is a functional narrowing — no user could have been resolved onto
  those versions; the bounds simply described versions that do not work. With
  them corrected, the full suite passes at the floors on Julia 1.10.

- **`to_julia` on a `STRNG` now returns the characters, not GIAC's printed
  literal.** `to_julia(giac_eval("\"hello\""))` answered `"\"hello\""` — the
  source literal, double quotes included — where the documented conversion
  table promises `STRNG` → `String`. Every caller had to strip the quotes,
  and stripping is not enough in general: GIAC escapes an embedded quote by
  doubling it, so `a"b` prints as `"a""b"` and dropping the first and last
  character leaves `a""b`.

  `_convert_to_string` returned `string(g)`, which is GIAC's *print* form,
  while the wrapper had exposed the payload directly as `strng_value` all
  along without the conversion path using it. It now reads the characters
  from the wrapper, so `to_julia(giac_eval("\"hello\""))` is `"hello"`, an
  empty GIAC string converts to `""`, and Unicode content survives intact. A
  `STRNG` holding digits still converts to a `String` — the characters are
  the value, and `to_julia` does not re-parse them.

  `strng_value` dereferences the payload *without checking the tag* — handed
  anything else it segfaults the process rather than raising. The helper
  therefore checks the tag itself, and checks it on the very `Gen` it is about
  to dereference: `giac_type` would not do, because it re-parses the printed
  form and reports the type of the result, which is a different `Gen` from the
  cached one being read. No expression is known where the two disagree, but
  that is not a gap to leave open in front of a segfault.

  **Behaviour change.** Code that worked around the old output — stripping
  the first and last character, matching on `"\"...\""`, or comparing against
  a quoted literal — must drop the workaround. Code that used `string(expr)`
  to obtain the literal form is unaffected: `string` still prints the GIAC
  literal, quotes and all.

## [0.14.2] - 2026-07-24

### Fixed

- **`latex` and `mathml` no longer re-evaluate their argument**:
  `latex(ifactor(360))` returned `"360"` instead of the factorization, and
  the same expression rendered as `360` in any notebook that consumes the
  `text/latex` MIME type (Pluto, Jupyter, KaimonSlate).
  GIAC evaluates command arguments, and `ifactor(360)` is the product
  `2^3*3^2*5`, which evaluates straight back to `360` — so the form was
  lost before it could be typeset. `invoke_cmd` now quotes the `GiacExpr`
  arguments of the rendering commands listed in `Giac.RENDER_COMMANDS`
  (`:latex`, `:mathml`), on both the direct-`Gen` fast path and the string
  path, so they typeset the expression as given:
  `latex(ifactor(360))` → `"5\cdot 2^{3}\cdot 3^{2}"`. Every other command
  keeps GIAC's normal evaluation semantics. Reported by
  [@kahliburke](https://github.com/kahliburke).

## [0.14.1] - 2026-05-11

### Added

- **MCP server integration**: `giac_mcp_server()` exposes Giac's CAS engine
  to MCP-aware LLM clients (Claude Desktop, Claude Code, Cursor, …) through
  a new weak-dependency package extension `GiacMCPExt` on
  [`ModelContextProtocol.jl`](https://github.com/JuliaSMLM/ModelContextProtocol.jl).
  The server advertises two tools — `giac_eval` (Giac/Xcas expression in →
  textual result out, with `CallToolResult(isError=true, ...)` for genuine
  Julia exceptions) and `giac_search` (keyword in → matching command names
  out, with a prefix-then-substring fallback so LLM-style queries like
  `"matrix"` or `"prime"` surface relevant commands). The MCP `initialize`
  handshake's `serverInfo.version` defaults to the running Giac.jl version
  so clients always see the right number. Users who do not load
  `ModelContextProtocol.jl` are unaffected — no transitive dependency, no
  precompilation cost. See `docs/src/extensions/mcp.md` for the full setup
  guide.

- **Example MCP prompts in the documentation**: `docs/src/extensions/mcp.md`
  now ships a curated "Example prompts" gallery — French and English
  direct-style prompts (`factorise avec giac x²-1`, `with giac, factor
  x^4 - 1`) plus natural-language, story-style prompts that exercise the
  LLM's judgement when routing to `giac_eval` (e.g., *"between which two
  integers does the real root of x^3 + x - 1 = 0 lie?"*, *"my password is
  the prime just after one billion — what is it?"*). A separate
  `giac_search` block shows catalogue-discovery prompts
  (*"which commands deal with matrices?"*).

- **Direct `Gen` fast path for `invoke_cmd` / `giac_cmd` (spec 069)**: the
  generic command dispatcher now bypasses the GIAC parser when all arguments
  have a direct `Gen` representation (`GiacExpr`, `Int32`, Int32-fitting
  `Int64`, finite `Float64`). The path resolves arguments through
  `_get_gen_or_eval` / `Gen(Int32(x))` / `Gen(Float64(x))` and routes to
  `apply_func0`/`apply_func1`/`apply_func2`/`apply_func3` (positional, zero
  `StdVector` allocation) for arity 0–3 and `apply_funcN` with a
  `StdVector{Gen}` for arity ≥ 4. Geometric-mean speed-up across the standard
  workload mix is ≈ 1.5× with per-workload wins up to ≈ 2× on commands whose
  result is a long symbolic expression (`factor`, `expand`). The existing
  string-concatenation path is preserved as a fallback for `Rational`,
  `Complex`, `AbstractIrrational`, `AbstractVector`, `GiacMatrix`,
  `±Inf`/`NaN`, `Symbol`, `String`, `DerivativeCondition`, `DerivativePoint`,
  `Function`, `BigInt`, `Int128`, and out-of-Int32-range `Int64` — all
  existing call shapes continue to work unchanged. Beyond the speed-up, the
  fast path structurally eliminates the `Gen → string → parse → Gen`
  round-trip class of bug that motivated `_giac_subst_vec_tier1` (spec 065).
  Set `GIAC_INVOKE_CMD_STRING_PATH=1` to disable globally.

- **`CONTRIBUTORS.md`**: a top-level acknowledgements file listing the
  people who built, reviewed, and inspired this package — Giac authors
  (Bernard Parisse & Renée De Graeve), the original `Giac.jl`
  (Harald Hofstaetter), Julia ecosystem reviewers (Viral B. Shah,
  Mosè Giordano, Max Horn), code contributors (John Verzani),
  feature/bug-report contributors (Thibault Duretz), and methodology
  inspiration (Sam Abbott). Linked from the README.

### Fixed

- **`D` operator now accepts Unicode identifiers**: `D(ϕ)` on a function
  variable defined as `@giac_var 𝑧 ϕ(𝑧)` previously failed with
  `ArgumentError: D() requires a function expression like u(t)`. The
  internal parser regex (`_parse_function_expr`) only matched ASCII
  letters, even though GIAC C++ and Julia both accept Unicode names. The
  regex now uses Unicode letter/number classes (`\p{L}`, `\p{N}`), so
  Greek letters, mathematical italics, and other Unicode identifiers work
  with `D(u)`, `D(u, n)`, and chained forms. Reported by
  [@tduretz](https://github.com/tduretz).

- **`is_constant` now recognizes the GIAC `infinity` and `undef`
  atoms.** Previously, `is_constant(giac_eval("inf"))` returned `false`
  because `infinity` was treated as a free identifier. After this fix,
  any expression built from these atoms — including `inf`, `+inf`,
  `-inf`, `+infinity`, `-infinity`, `unsigned_inf`, `1/0` (which GIAC
  evaluates to `+infinity`), and `0/0` (which evaluates to `undef`) —
  is correctly classified as a constant. `Giac.Constants.is_giac_constant`
  picks up these atoms via a name-based fallback, since GIAC's internal
  `==` reports `infinity == infinity` as `false`. As a follow-on fix,
  `to_julia` no longer infinitely recurses on these irreducible atoms
  (`evalf` is a no-op on them); it returns the `GiacExpr` unchanged,
  matching the prior public behavior. Closes
  [#19](https://github.com/s-celles/Giac.jl/issues/19).

  Note: names like `nan`, `NaN`, `unsigned_infinity`, and `undefined`
  are *not* GIAC atoms — GIAC parses them as ordinary free identifiers
  (e.g. `nan + 1` yields `nan+1` exactly like `xyz + 1` yields `xyz+1`),
  so they remain non-constant.

## [0.14.0] - 2026-05-02

### Added

- **`build_function` Symbolics backend (Tier 3)**: a new `backend::Symbol`
  keyword on `build_function` selects the evaluation engine. The default
  `backend = :giac` is unchanged from v0.13. The new `backend = :symbolics`
  (requires `using Symbolics`) round-trips the expression through
  `to_symbolics` and compiles it via `Symbolics.build_function`, returning a
  native Julia callable that is autodiff-friendly (ForwardDiff, SciML
  solvers) and typically at least an order of magnitude faster in hot
  loops. Documented in
  [`docs/src/julia_functions.md`](docs/src/julia_functions.md), with a
  comparison table and a runtime benchmark.

  Error paths: `backend = :symbolics` without `using Symbolics`, free
  symbols not bound by `vars`, GIAC heads with no `to_symbolics`
  translation, and bad backend symbols all surface as actionable
  `ArgumentError`s at `build_function` time. Closes
  [#17](https://github.com/s-celles/Giac.jl/issues/17) Tier 3.

  Naming caveat: `Symbolics` also exports `build_function`; with both
  `using Giac` and `using Symbolics` in scope, qualify as
  `Giac.build_function(...)` (this is the standard Julia convention for
  name conflicts and is documented in the docstring and docs page).
  (067-build-function-tier3)

## [0.13.0] - 2026-05-02

### Added

- **`build_function`**: convert a `GiacExpr` into a native Julia callable
  with one named call. `f = build_function(expr, x, y)` returns a closure
  satisfying `f(a, b) == to_julia(substitute(expr, x => a, y => b))`, suitable
  as a drop-in argument to `Plots.plot`, `Plots.surface`, broadcasting
  (`f.(xs)`), and matrix comprehensions. The wrapper is intentionally thin —
  it composes the existing `substitute` + `to_julia` chain — and the
  underlying primitives remain available for cases that need a custom step
  in between. Documented in
  [`docs/src/julia_functions.md`](docs/src/julia_functions.md), with a
  comparison table to `Symbolics.build_function` and SymPy's `lambdify`, and
  showcased in the existing `examples/04_plotting.jl` Pluto notebook.
  Closes [#17](https://github.com/s-celles/Giac.jl/issues/17).
  (066-build-function)

## [0.12.0] - 2026-05-01

### Added

- **Varargs `substitute`**: `substitute(expr, x => 1, y => 2)` and the matching
  `GiacMatrix` form now accept any number of `Pair` arguments, aligned with
  `Symbolics.substitute`. Equivalent to the dict form `substitute(expr, Dict(pairs))`;
  all pairs are applied simultaneously. Calling with zero pairs returns the input
  unchanged. (065-substitute-tier1)
- **Call-syntax substitution**: a `GiacExpr` called with pair arguments now performs
  substitution. `expr(a => 15, b => 10, c => 5, d => 0)` is equivalent to
  `substitute(expr, a => 15, b => 10, c => 5, d => 0)` and inherits its simultaneous
  semantics. The existing function-evaluation call shape (`u(0)`, `f(x)`) is
  unchanged because the new method dispatches only on `Pair{<:GiacExpr}...`.
  Idea contributed by [@jverzani](https://github.com/jverzani) in
  [PR #11](https://github.com/s-celles/Giac.jl/pull/11). (065-substitute-tier1)
- **Julia `Function` arguments accepted by GIAC commands**: `_arg_to_giac_string`
  now serializes a `Function` value as `string(nameof(arg))`, so callers can pass
  a Julia function directly where the GIAC command expects a function name —
  e.g. `combine(log(x) + 2*log(x), log)` instead of `combine(..., "log")`. As a
  side effect, the same fallback also lets `substitute` accept a `Function`
  value (`substitute(f, f => log)` yields `log`). Contributed by
  [@jverzani](https://github.com/jverzani) in
  [PR #6](https://github.com/s-celles/Giac.jl/pull/6).
- **Additional math operations on `GiacExpr`** — degree-based and pi-multiple
  trig variants (`sind`, `cosd`, `sinpi`, `cospi`, `asind`, `acosd`, `atand`,
  `secd`, `cscd`, `cotd`), paired trig (`sincos`, `sincosd`, `sincospi` —
  return a 2-tuple of `GiacExpr`), angle conversion (`deg2rad`, `rad2deg`),
  exponential / logarithm extensions (`exp2`, `exp10`, `log1p`, two-argument
  `log(b, x)` for any base), `adjoint` (so postfix `'` works on `GiacExpr`),
  and `zero` / `one` (instance and `::Type{GiacExpr}` forms). Contributed by
  [@jverzani](https://github.com/jverzani) in
  [PR #9](https://github.com/s-celles/Giac.jl/pull/9).
- **`GiacMatrix` iteration and linear indexing**: `length(M)` returns
  `rows * cols`; `for e in M` and `collect(M)` walk the entries in
  column-major order (matching Julia's `Matrix` convention); `M[i]` and
  `M[CartesianIndex(i, j)]` provide linear and Cartesian indexing; and
  `LinearIndices(M)` / `CartesianIndices(M)` are available for converting
  between forms. Contributed by [@jverzani](https://github.com/jverzani) in
  [PR #10](https://github.com/s-celles/Giac.jl/pull/10).
- **Introspection helpers**: `is_constant`, `unwrap_const`, `free_symbols`,
  `hasmatch`, `iscall`, `operation`, `arguments`, `maketerm`,
  `Constants.is_giac_constant`, identity constructor `GiacExpr(::GiacExpr)`.
  These let callers query whether an expression is closed-form constant,
  enumerate its free symbols, and walk it as a syntax tree. Contributed by
  [@jverzani](https://github.com/jverzani) in
  [PR #8](https://github.com/s-celles/Giac.jl/pull/8). Resolves
  [issue #3](https://github.com/s-celles/Giac.jl/issues/3).
- **TermInterface.jl extension** (`GiacTermInterfaceExt`): when
  `TermInterface` is loaded, `GiacExpr` participates in the
  `iscall` / `operation` / `arguments` / `maketerm` / `isexpr` protocol
  used by Metatheory.jl, SymbolicUtils.jl, and other rewriters. Pure
  weak-dep — no cost to users who don't load `TermInterface`.
- **`Base.isfinite(::GiacExpr)`**: returns a Julia `Bool`. `isfinite(x)` is
  `true` for free identifiers, ordinary symbolic expressions, and finite
  numbers; `false` for `inf`, `-inf`, and `1/0` (which GIAC normalizes to
  infinity). Implemented as `!to_julia(isinf(expr))::Bool`.
- **CommonSolve.jl integration**: `Giac.Commands.solve` is now the same generic
  function as `CommonSolve.solve` (`Giac.Commands.solve === CommonSolve.solve`),
  so Giac's `solve` participates in the broader Julia "solve" verb ecosystem
  alongside `DifferentialEquations.jl`, `NLsolve.jl`, `Symbolics.jl`, etc.
  Dispatch is by argument type, so there is no conflict — `solve(::GiacExpr, …)`
  routes to GIAC, `solve(::ODEProblem, …)` routes to DifferentialEquations,
  and so on. `CommonSolve` is a tiny hard dependency (~50 LOC, compat `0.2`).
  Note that `CommonSolve` also exports `init` and `solve!` as part of an
  iterative-solver protocol; Giac is a symbolic CAS (non-iterative) so only
  `solve` is extended — `init` and `solve!` are left untouched and remain
  available for other packages to extend without conflict.
  Contributed by [@jverzani](https://github.com/jverzani) in
  [PR #7](https://github.com/s-celles/Giac.jl/pull/7).

### Changed

- **`to_julia(::GiacExpr)` now reduces free-variable-free expressions to
  numbers via `evalf`.** Previously, `to_julia(substitute(sin(x), x => 2))`
  returned `GiacExpr: sin(2)` — the symbolic form was preserved even though
  the caller asked for a Julia value. Now it returns `0.9092…` (a `Float64`).
  The layered design holds: `evalf(expr)` keeps you in Giac and returns a
  `GiacExpr` whose internal type is `DOUBLE`; `to_julia(expr)` bridges to a
  Julia number. Symbolic expressions with at least one free variable still
  pass through unchanged. **This is a behavior change for users who relied
  on `to_julia` of constant symbolic expressions returning a `GiacExpr`** —
  use `evalf(expr)` instead if you want a numeric `GiacExpr`. Resolves
  [issue #3](https://github.com/s-celles/Giac.jl/issues/3).

- **`^(::GiacExpr, ::Number)` and `^(::Number, ::GiacExpr)` widened**: powers
  on `GiacExpr` previously accepted only an `Integer` exponent; now any
  `Number` is accepted on either side via `promote`. Existing
  `^(::GiacExpr, ::Integer)` calls continue to work unchanged. Contributed by
  [@jverzani](https://github.com/jverzani) in
  [PR #9](https://github.com/s-celles/Giac.jl/pull/9).
- **`substitute(expr, dict)` no longer round-trips through the GIAC parser.** The
  dict-form `substitute` for both `GiacExpr` and `GiacMatrix` now calls the direct
  CxxWrap binding `giac_subst` with structured `Gen` vector arguments built via
  `make_vect`. Simultaneous-substitution semantics (e.g. `Dict(x => y, y => x)`
  swaps `x` and `y`) and the public API are unchanged. On a representative
  non-trivial expression with two pairs, this is roughly 1.5–2× faster than the
  prior string-round-trip implementation (machine-dependent), and floating-point
  replacement values are preserved exactly. (065-substitute-tier1)
- **`substitute(expr, pair)` single-pair method replaced** by the new varargs
  method. `substitute(expr, x => 1)` continues to work without change; the dispatch
  path simply delegates to the new varargs definition. (065-substitute-tier1)

### Fixed

- **`asind` / `acosd` / `atand`**: implementation was `asin(deg2rad(x))` etc.,
  which converted the input from degrees to radians instead of converting the
  angle output from radians to degrees (e.g. `asind(1)` returned
  `asin(π/180)` instead of `90`). Corrected to `rad2deg(asin(x))` (matches
  Julia Base). Note: GIAC keeps the result as `pi/2 * 180/pi`; calling
  `simplify` reduces it to the integer.
- **`sincos` / `sincosd` / `sincospi`**: return-type annotation was
  `::GiacExpr` but the body returned a 2-tuple, triggering a `MethodError`
  on every call. Annotation changed to `::Tuple{GiacExpr, GiacExpr}`.

### Removed

- Internal helper `_build_subst_command` (no longer needed; the substitution path
  no longer constructs subst-command strings). Not part of the public API.

## [0.11.2] - 2026-04-16

### Added

- **Symbolic comparison and logical operators on `GiacExpr`**: `<`, `>`, `<=`, `>=`,
  `&`, `|` are now defined for `GiacExpr`, allowing symbolic conditions to be
  expressed directly (e.g. `x < y`, `(x > 0) & (y < 1)`). (#4)

## [0.11.1] - 2026-04-11

### Fixed

- **`to_giac` with Symbolics v7 literal numbers**: handles symbolic literal numbers
  produced by Symbolics v7, fixing a `TypeError` when squaring or otherwise
  manipulating expressions converted from Symbolics. (#2, closes #1)

## [0.11.0] - 2026-04-06

### Added

- **JLL-based library loading**: `GIAC_jll` and `libgiac_julia_jll` are now direct
  dependencies, providing the GIAC library and C++ wrapper automatically. No manual
  compilation or environment variables needed.
- **Windows support**: Fixed POSIX `dup`/`dup2` calls in `search_commands_by_description`
  to use Windows-compatible `_dup`/`_dup2`.
- **Symbolics 7 compatibility**: `to_symbolics` now returns consistent `Num` type using
  `Symbolics.wrap()` and pairwise `Symbolics.term()` for multiplication, preserving
  symbolic forms like `sqrt(2)`.

### Removed

- **BREAKING**: Removed `is_stub_mode()` from public API. Stub mode no longer exists —
  the library is always available via JLL packages.
- **BREAKING**: Removed `TempApi` submodule. Use `Giac.Commands` instead for the same
  functions (`diff`, `integrate`, `factor`, etc.).
- Removed all stub mode infrastructure (`_stub_mode` flag, stub expressions, conditional
  branches in ~30 functions).

### Changed

- **BREAKING**: Minimum Julia version raised from 1.10 to 1.11.
- Library initialization now throws `GiacError` instead of silently falling back to
  stub mode when the wrapper library is not found.

## [0.10.0] - 2026-04-05

### Added

- **HeldCmd LaTeX rendering**: Specialized LaTeX renderers for `limit`, `sum`, `product`,
  and `sum_riemann` held commands.
- **HeldEquation tilde operator**: `~` operator support for `HeldCmd` with LaTeX rendering.
- **GiacMatrix command support**: GIAC commands now work with `GiacMatrix` arguments.
- `Base.numerator` and `Base.denominator` methods for `GiacExpr`.

## [0.9.0] - 2026-03-20

### Added

- **Symbolic Constants module (`Giac.Constants`)**: Submodule providing symbolic
  mathematical constants `pi`, `e`, and `i` as `GiacExpr` values:
  ```julia
  using Giac.Constants: pi, e, i
  expr = 2 * pi * x  # stays symbolic
  ```

- **MathJSON.jl extension**: Bidirectional conversion between `GiacExpr` and MathJSON
  expression trees via `to_mathjson` and `to_giac`.

- **Direct pointer conversion**: `to_symbolics` and `to_giac` use direct Gen pointer
  transfer instead of string serialization for better performance.

- **Direct GMP binary transfer**: `BigInt` conversion uses direct memory transfer from
  GIAC's GMP integers, avoiding string parsing.

### Changed

- `GiacSymbolicsExt` uses `GenTypes` enum instead of magic numbers.
- Factorized expressions preserved in `to_symbolics` conversion.

## [0.8.0] - 2026-03-15

### Added

- **GenTypes module**: `T` enum for GIAC expression types with C++ alignment.
- **Pluto example notebooks**: Basics and advanced usage notebooks with screenshots.

### Changed

- Tier 2 N-ary dispatch for functions with >3 parameters.

## [0.7.0] - 2026-03-10

### Added

- **UnitRange indexing**: `GiacMatrix` and `@giac_several_vars` support `UnitRange` indices.
- **Z-transform functions**: `ztrans` and `invztrans` with documentation.
- **Laplace transform functions**: `laplace` and `ilaplace` with documentation.
- **D operator**: Derivative operator for ODE initial conditions.
- **Callable GiacExpr**: `f(x)` syntax for function evaluation.
- **Extended `@giac_var` macro**: Function syntax support.

## [0.6.0] - 2026-03-05

### Added

- **Domain documentation**: Mathematics (algebra, calculus, linear algebra, ODEs,
  trigonometry) and physics (mechanics, electromagnetism) with test-verified examples.
- **Vector input support**: GIAC commands accept Julia vectors as arguments.
- **Boolean conversion**: `to_julia` handles GIAC boolean results.

### Fixed

- `to_julia` for `solve` results using CxxWrap bindings.
- Correct `GIAC_STRNG` type constant.

## [0.5.0] - 2026-02-25

### Added

- **Tables.jl compatibility**: `GiacMatrix` and command help implement Tables.jl interface.
- **Julia help system integration**: `?command` works in the REPL.
- **Variable substitution**: `substitute` function with Symbolics.jl-compatible interface.
- **Output handling**: Improved type conversion and introspection.

### Removed

- Public `help()` function (replaced by Julia help system integration).

## [0.4.0] - 2026-02-20

### Added

- **Multiple dispatch for JULIA_CONFLICTS commands**: GIAC commands that conflict with
  Julia (like `zeros`, `min`, `max`, `det`, `inv`) now work with `GiacExpr` arguments
  via multiple dispatch.

- **Equation syntax with `~` operator**: Create symbolic equations using the tilde operator:
  ```julia
  @giac_var x
  eq = x^2 - 1 ~ 0
  solve(eq, x)
  ```

### Changed

- Suppressed misleading conflict warnings for non-keyword conflicts.

## [0.3.0] - 2026-02-16

### Removed

- **BREAKING**: Removed `giac_` prefixed functions in favor of `Giac.Commands` equivalents.

### Changed

- `Giac.TempApi` delegated to `invoke_cmd` instead of removed `giac_*` functions.

## [0.2.0] - 2026-02-16

### Changed

- **BREAKING**: Renamed `@giac_several_var` to `@giac_several_vars` (plural form).

## [0.1.0] - Initial Release

### Added

- Core symbolic expression type `GiacExpr`
- Expression evaluation with `giac_eval`
- Calculus operations: `giac_diff`, `giac_integrate`, `giac_limit`, `giac_series`
- Algebraic operations: `giac_factor`, `giac_expand`, `giac_simplify`, `giac_solve`, `giac_gcd`
- Symbolic variable macros: `@giac_var`, `@giac_several_vars`
- Matrix type `GiacMatrix` with `det`, `inv`, `tr`, `transpose`
- Command discovery: `list_commands`, `search_commands`, `suggest_commands`
- Commands submodule with ~2000 GIAC commands
- Performance tier system (Tier 1/2/3)
- Thread-safe evaluation with `GiacContext`
