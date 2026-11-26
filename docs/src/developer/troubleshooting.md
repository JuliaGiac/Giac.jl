# Troubleshooting

This guide covers common issues encountered when developing with Giac.jl and strategies for debugging them.

## Library Loading Errors

### libgiac_jll Issues

**Symptom**: Error on `using Giac` mentioning missing library or symbols.

```
ERROR: LoadError: could not load library "libgiac"
```

**Causes and Solutions**:

1. **Missing JLL package**:
   ```julia
   using Pkg
   Pkg.add("libgiac_jll")
   ```

2. **Version mismatch**: Ensure compatible versions:
   ```julia
   Pkg.status("libgiac_jll")
   Pkg.status("CxxWrap")
   ```

3. **Corrupted installation**:
   ```julia
   Pkg.rm("Giac")
   Pkg.gc()  # Clean up
   Pkg.add("Giac")
   ```

### CxxWrap Compatibility

**Symptom**: Errors about missing methods or incorrect types.

```
ERROR: MethodError: no method matching ...
```

**Causes**:

1. **CxxWrap version mismatch**: Check versions match what Giac.jl expects
   ```julia
   Pkg.status("CxxWrap")
   ```

2. **Recompilation needed**:
   ```julia
   using Pkg
   Pkg.build("Giac")
   ```

### RTLD_GLOBAL Requirement

**Symptom**: Symbols not found at runtime despite library loading.

```
ERROR: symbol "giac_..." not found
```

**Cause**: The C++ library wasn't loaded with `RTLD_GLOBAL` flag.

**Fix**: This should be handled automatically by Giac.jl's `init_giac_library()`. If you see this error:

1. Check that `__init__()` is being called
2. Verify the library loading code in `wrapper.jl`:
   ```julia
   # Should use RTLD_GLOBAL
   Libdl.dlopen(lib_path, RTLD_GLOBAL | RTLD_LAZY)
   ```

## Runtime Errors

### GiacError Types

Giac.jl categorizes errors with a `category` field:

| Category | Description | Common Causes |
|----------|-------------|---------------|
| `:parse` | GIAC couldn't parse the expression | Syntax error in expression string |
| `:eval` | Evaluation failed | Unknown command, domain error |
| `:type` | Type conversion error | Incompatible types |
| `:memory` | Memory-related error | Null pointer, freed object |

**Debugging**:

```julia
try
    result = giac_eval("invalid(")
catch e
    if e isa GiacError
        println("Category: ", e.category)
        println("Message: ", e.message)
    end
    rethrow()
end
```

### Unknown Command Errors

**Symptom**:
```
GiacError: Unknown command: myfunction
```

**Causes**:

1. **Typo in command name**:
   ```julia
   giac_cmd(:factr, x)  # Wrong: should be :factor
   ```

2. **Command not in GIAC**: Not all mathematical functions are in GIAC
   ```julia
   # Check if command exists
   using Giac: VALID_COMMANDS
   :my_function in VALID_COMMANDS
   ```

3. **Command suggestions**: Giac.jl suggests similar commands:
   ```
   Unknown command: factr. Did you mean: factor?
   ```

### Type Conversion Failures

**Symptom**:
```
ERROR: Cannot convert GiacExpr to Float64
```

**Causes and Solutions**:

1. **Expression is symbolic**:
   ```julia
   x = giac_eval("x")
   to_julia(x)  # Error: x is symbolic

   # Fix: Evaluate numerically first
   to_julia(giac_cmd(:evalf, x))  # Still symbolic

   # Or: Use numeric values
   x = giac_eval("3.14")
   to_julia(x)  # Works: 3.14
   ```

2. **Complex result**:
   ```julia
   result = sqrt(giac_eval("-1"))
   to_julia(Float64, result)  # Error: result is complex

   # Fix: Use Complex type
   to_julia(ComplexF64, result)  # Works
   ```

### Different Results on Another Thread

**Symptom**: with Julia started with several threads (`julia -t 4`), a task
started with `Threads.@spawn` does not see a variable bound with `:=`, a
setting such as `Digits`, or an assumption made with `assume` or
`@giac_var x::positive` on the main thread.

**Cause**: GIAC's default context is per OS thread. See
[Threads](memory.md#Threads) in the memory guide.

**Fix**: pass an explicit `GiacContext` to `giac_eval(string, ctx)`, which
every thread shares, or run the work in `@async` tasks, which stay on the
thread that starts them.

## Performance Issues

### Identifying Tier Fallbacks

If operations seem slower than expected, a function may be falling back from Tier 1 to Tier 3.

**Debug strategy**:

```julia
# Enable debug logging
ENV["JULIA_DEBUG"] = "Giac"

# Run your operation
result = sin(giac_eval("x"))

# Check logs for fallback messages:
# "Tier 1 function failed: ..."
```

**Common causes of fallback**:

1. **C++ exception**: Error in the C++ wrapper
2. **Invalid input**: Pointer is null or invalid

### Profiling Tips

**Using Julia's profiler**:

```julia
using Profile

# Profile the operation
@profile for i in 1:10000
    sin(giac_eval("x"))
end

# View results
Profile.print()
```

**Benchmarking tiers**:

```julia
using BenchmarkTools

x = giac_eval("x")

# Benchmark Tier 1 path
@btime sin($x)

# Force Tier 3 path for comparison
@btime giac_cmd(:sin, $x)
```

### Memory Allocation Tracking

**Check for excessive allocations**:

```julia
@time begin
    for i in 1:1000
        x = giac_eval("x^$i")
    end
end
```

**Force GC to check for leaks**:

```julia
GC.gc()
initial = Sys.maxrss()

for i in 1:10000
    x = giac_eval("x^2")
end

GC.gc()
final = Sys.maxrss()
println("Memory growth: $(final - initial) bytes")
```

## Test Failures

### Common Test Failure Causes

1. **String representation changes**:
   ```julia
   # May fail if GIAC changes output format
   @test string(factor(x^2 - 1)) == "(x-1)*(x+1)"

   # More robust:
   @test expand(factor(x^2 - 1)) == x^2 - 1
   ```

2. **Floating point precision**:
   ```julia
   # May fail due to precision
   @test to_julia(sin(giac_eval("pi/6"))) == 0.5

   # Better:
   @test to_julia(sin(giac_eval("pi/6"))) ≈ 0.5
   ```

3. **Order-dependent results**:
   ```julia
   # Polynomial terms may appear in different orders
   @test string(expand(x+y)) == "x+y"  # May be "y+x"

   # Better: Compare evaluated equality
   result = expand((x+1)*(x-1))
   @test giac_cmd(:expand, result - (x^2 - 1)) == giac_eval("0")
   ```

### Debugging Test Failures

**Run single test**:

```julia
using Pkg
Pkg.test("Giac", test_args=["--testset", "sin function"])
```

**Interactive debugging**:

```julia
using Giac

# Reproduce the test manually
x = giac_eval("x")
result = sin(x)
@show result
@show string(result)
@show typeof(result)
```

**Check test environment**:

```julia
# Ensure clean state
GC.gc()

# Check context
@show Giac.DEFAULT_CONTEXT
```

## Debugging Strategies

### Isolating Julia vs C++ Issues

**Step 1**: Check if the issue is in argument conversion:
```julia
# Test argument conversion
expr = giac_eval("x")
@show Giac._arg_to_giac_string(expr)
```

**Step 2**: Check if GIAC understands the command:
```julia
# Direct string evaluation
result = giac_eval("sin(x)")  # Bypasses Julia wrappers
```

**Step 3**: Check the tier being used:
```julia
# Enable debug mode
ENV["JULIA_DEBUG"] = "Giac"

# Run operation
sin(giac_eval("x"))
# Look for tier fallback messages
```

### Using GIAC Directly

For advanced debugging, test in GIAC directly:

```bash
# Install GIAC CLI (if available)
giac

# Test commands directly
>> sin(x)
>> factor(x^2-1)
```

### Wrapper Layer Debugging

**Check wrapper availability**:
```julia
using Giac: GiacCxxBindings

# Check if wrapper is loaded
@show GiacCxxBindings._have_library

# List available functions
names(GiacCxxBindings)
```

## Getting Help

### GitHub Issues

For bugs or feature requests:

1. Search existing issues at [github.com/s-celles/Giac.jl/issues](https://github.com/s-celles/Giac.jl/issues)
2. Create a new issue with:
   - Giac.jl version (`Pkg.status("Giac")`)
   - Julia version (`VERSION`)
   - Minimal reproducible example
   - Full error message with stack trace

### Providing Debug Information

Include this information in bug reports:

```julia
using Pkg
using Giac

println("Julia: ", VERSION)
println("Giac.jl: ", Pkg.dependencies()[Base.PkgId(Giac).uuid].version)
println("CxxWrap: ", Pkg.dependencies()[Base.PkgId(CxxWrap).uuid].version)
println("Platform: ", Sys.MACHINE)
println("OS: ", Sys.KERNEL)
```

### Community Resources

- **Julia Discourse**: [discourse.julialang.org](https://discourse.julialang.org) - Tag with `giac` or `computer-algebra`
- **Julia Slack/Zulip**: `#mathematics` channel
- **GIAC Documentation**: [www-fourier.univ-grenoble-alpes.fr/~parMDisse/giac.html](https://www-fourier.univ-grenoble-alpes.fr/~parisse/giac.html)

## See Also

- [Memory Management](memory.md) - For memory-related issues
- [Performance Tiers](tier-system.md) - Understanding tier fallbacks
- [Package Architecture](architecture.md) - Where to find source code
