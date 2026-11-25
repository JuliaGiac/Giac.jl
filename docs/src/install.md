# Installation

## Installing Giac.jl

```julia
using Pkg

Pkg.add("Giac")  # when registered in Julia General Registry
# or
Pkg.add(url="https://github.com/s-celles/Giac.jl")  # until unregistered
```

The Giac computer algebra library and its C++ wrapper are provided automatically via JLL packages (`GIAC_jll` and `libgiac_julia_jll`). No manual compilation or environment variables are needed.

### Requirements

- Julia 1.10 or later

### Verifying Installation

```julia
using Giac

# Verify GIAC integration is working
result = giac_eval("factor(x^2 - 1)")
println(result)  # (x-1)*(x+1)
```

## Developer Installation (Custom Wrapper)

If you need to use a custom-built wrapper library (e.g., for development or debugging), set the `GIAC_WRAPPER_LIB` environment variable before starting Julia:

```bash
export GIAC_WRAPPER_LIB=/path/to/libgiac_wrapper.so
julia
```

This overrides the JLL-provided library. The environment variable must be set before Julia precompiles the package.
