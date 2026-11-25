# Using Giac.jl with reactive notebooks

`GiacExpr` and `GiacMatrix` values render as typeset mathematics in any
notebook that understands the `text/latex` MIME type. Two reactive notebook
environments are covered here: [Pluto](#Pluto) and [KaimonSlate](#KaimonSlate).
In both, changing a cell re-runs the cells that depend on it.

## Pluto

[Pluto.jl](https://plutojl.org/) notebooks are plain Julia files. Install
Pluto with `using Pkg; Pkg.add("Pluto")`, then open one of the example
notebooks shipped in `examples/`.

### LaTeX Rendering in Pluto

GiacExpr and GiacMatrix automatically render as LaTeX in Pluto notebooks! No extra conversion needed:

```julia
using Giac

f = giac_eval("2/(1-x)")  # Automatically displays as LaTeX fraction
df = invoke_cmd(:diff, f, giac_eval("x"))  # Derivative also renders as LaTeX

M = GiacMatrix([1 2; 3 4])  # Matrices render as LaTeX too
```

This works because Giac.jl implements `Base.show(io, ::MIME"text/latex", expr)` which calls Giac's native `latex` command.

### Rendering preserves the expression you computed

GIAC evaluates the arguments of every command, and not every result is a fixed
point of evaluation. The integer factorization `ifactor(360)` is the product
`2^3*3^2*5`, which evaluates straight back to `360`. Giac.jl therefore quotes
`GiacExpr` arguments passed to the rendering commands (`latex` and `mathml`),
so they typeset the expression as it stands instead of a re-evaluated copy:

```julia
using Giac
using Giac.Commands: ifactor, latex

f = ifactor(360)   # 2^3*3^2*5
latex(f)           # "5\cdot 2^{3}\cdot 3^{2}"  (not "360")
```

The same holds for notebook display, so an `ifactor` result shows the
factorization rather than the original number in any frontend that consumes
the `text/latex` MIME type — Pluto, Jupyter, or KaimonSlate:

```julia
ifactor(360)       # renders as 5·2³·3²
```

Every other command keeps GIAC's normal evaluation semantics — only `latex`
and `mathml` hold their argument, because they are the ones whose job is to
show an expression rather than compute with it.

A demo notebook is available at `examples/02_latex.jl`:

```julia
using Pluto
Pluto.run(notebook="examples/02_latex.jl")
```

### Symbolic ODEs and PDEs

A worked-example notebook covering symbolic ODE solutions via `desolve` (first-order, harmonic and damped oscillators, third-order, RLC, forced) and partial-differential-equation expressions (heat, wave, transport, separation of variables for the heat equation) using the canonical `Differential` operator from spec 068. All cells are reactive — change a coefficient or initial condition and downstream cells update.

```julia
using Pluto
Pluto.run(notebook="examples/07_odes_pdes.jl")
```

### Other example notebooks

- `examples/01_basics.jl` — symbolic operations primer
- `examples/02_latex.jl` — LaTeX-rendering demo (referenced above)
- `examples/03_examples.jl` — comprehensive showcase by domain
- `examples/04_plotting.jl` — symbolic-to-plotting pipelines
- `examples/05_programming.jl` — multi-line GIAC programs
- `examples/06_symbolics_bridge.jl` — Giac.jl × Symbolics.jl interop

See screenshots:

![screencapture-pluto-notebook](assets/screencapture-pluto-notebook-latex_demo.png)

![screencapture-basics.png](assets/screencapture-basics.png)

![screencapture-examples.png](assets/screencapture-examples.png)

![screencapture-examples-2.png](assets/screencapture-examples-2.png)

## KaimonSlate

[KaimonSlate](https://github.com/kahliburke/KaimonSlate.jl) is a reactive
notebook environment for Julia. [GiacSlate.jl](https://juliagiac.github.io/GiacSlate.jl/dev/)
integrates Giac.jl with it. It adds live math input fields (MathLive), which
you write with the `giac"..."` string macro or embed in Markdown prose, and an
autograder for exercises. Results render as typeset mathematics.

GiacSlate is not registered yet; install it from its repository. Giac.jl comes
with it as a dependency:

```julia-repl
pkg> add https://github.com/JuliaGiac/GiacSlate.jl
```

A notebook cell loads Giac.jl and GiacSlate like any other packages:

```julia
using Giac
using Giac.Commands: integrate
using GiacSlate   # turns on the inline math editor

@giac_var x
integrate(1 / (1 + x^2), x)   # shown as typeset mathematics
```

GiacSlate ships four example notebooks, which open with the `slate` command
line tool from KaimonSlate:

```sh
git clone https://github.com/JuliaGiac/GiacSlate.jl.git
cd GiacSlate.jl
slate notebooks/giac_intro.jl
```

- `giac_intro.jl`: symbolic computation with Giac.jl (calculus, linear
  algebra, interactive Taylor series). Start here.
- `giac_tour.jl`: a tour of the Giac engine, driven through live math fields.
- `laplace_lesson.jl`: a physics lesson on the Laplace transform with
  self-grading exercises.
- `custom_controls.jl`: a playground for custom Slate widgets.

The [GiacSlate documentation](https://juliagiac.github.io/GiacSlate.jl/dev/)
covers the math input, the autograder and its API, and renders every notebook
as a page.
