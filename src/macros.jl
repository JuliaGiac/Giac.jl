# Macro definitions for Giac.jl
# Feature: 011-giac-symbol-macro
# Feature: 012-giac-several-var
# Feature: 033-giac-var-function

# Helper functions for @giac_several_vars

"""
    _needs_separator(dims) -> Bool

Check if any dimension exceeds 9, requiring underscore separators in variable names.
When any dimension > 9, indices could be >= 10 and need separators for clarity.
Also returns true if any index could be negative (requires separator).
"""
function _needs_separator(dims)
    return any(d -> d > 9, dims)
end

"""
    _needs_separator_for_macro_ranges(ranges) -> Bool

Check if underscore separators are needed for ranges in macro context.
Returns true if any range has an index > 9 or < 0.
"""
function _needs_separator_for_macro_ranges(ranges)
    for r in ranges
        if !isempty(r) && (minimum(r) < 0 || maximum(r) > 9)
            return true
        end
    end
    return false
end

"""
    _is_range_expr(expr) -> Bool

Check if an expression is a range expression (a:b or a:b:c).
"""
function _is_range_expr(expr)
    return expr isa Expr && expr.head == :call && expr.args[1] == :(:)
end

"""
    _eval_dim_to_range(dim)

Convert a dimension specification to a range.
Integer n becomes 1:n for backward compatibility.
Range expressions are evaluated to actual ranges.
"""
function _eval_dim_to_range(dim)
    if dim isa Integer
        return 1:dim
    elseif _is_range_expr(dim)
        # Evaluate range expression at macro expansion time
        return eval(dim)
    else
        throw(ArgumentError("Dimension must be integer or range expression, got $(typeof(dim)): $dim"))
    end
end

"""
    _format_index(idx::Integer) -> String

Format a single index for use in variable names.
Negative indices are encoded with 'm' prefix (e.g., -1 → "m1") to avoid
GIAC interpreting the minus sign as a subtraction operator.
"""
function _format_index(idx::Integer)
    if idx < 0
        return "m" * string(-idx)
    else
        return string(idx)
    end
end

"""
    _format_indices(base::Symbol, indices::Tuple, needs_sep::Bool) -> Symbol

Generate a variable name from base name and indices.
If needs_sep is true, uses underscore separators (e.g., `a_1_10_3`).
Otherwise, concatenates indices directly (e.g., `a123`).
Negative indices are encoded with 'm' prefix (e.g., -1 → `a_m1`).
"""
function _format_indices(base::Symbol, indices::Tuple, needs_sep::Bool)
    formatted = [_format_index(idx) for idx in indices]
    if needs_sep
        return Symbol(base, "_", join(formatted, "_"))
    else
        return Symbol(base, join(formatted))
    end
end


"""
    @giac_several_vars base dims...

Create multiple indexed symbolic variables for N-dimensional tensors.

This macro generates multiple `GiacExpr` variables in the calling scope
with names formed from a base name and indices. It supports any number
of dimensions and returns a tuple of all created variables.

# Arguments
- `base`: Symbol - The base name for variables (e.g., `a`, `coeff`, `α`)
- `dims...`: Integer literals or range expressions - Dimensions of the tensor (1 or more)
  - Integer `n`: Creates indices 1:n (backward compatible)
  - UnitRange `a:b`: Creates indices from a to b
  - StepRange `a:s:b`: Creates indices from a to b with step s

# Returns
- `Tuple{GiacExpr...}`: A tuple containing all created variables in lexicographic order

# Naming Convention
- If all indices are in 0-9: indices are concatenated directly (e.g., `a123`)
- If any index > 9: underscore separators are used (e.g., `a_1_10`)
- Negative indices: `m` prefix for minus (e.g., -1 → `m1`, so `c_m1`)

# Examples

1D vector:
```julia
@giac_several_vars a 3
# Creates: a1, a2, a3 and returns (a1, a2, a3)
a1 + a2 + a3  # Symbolic sum

# Capture return value
vars = @giac_several_vars c 4
length(vars)  # 4
```

2D matrix:
```julia
result = @giac_several_vars m 2 3
# Creates: m11, m12, m13, m21, m22, m23
# Returns: (m11, m12, m13, m21, m22, m23)
length(result)  # 6
```

3D tensor:
```julia
@giac_several_vars t 2 2 2
# Creates: t111, t112, t121, t122, t211, t212, t221, t222
# Returns tuple of 8 variables
```

Large dimensions (separator used):
```julia
@giac_several_vars b 2 10 3
# Creates: b_1_1_1, b_1_1_2, ..., b_2_10_3
```

Unicode base names:
```julia
@giac_several_vars α 2
# Creates: α1, α2
```

0-based indexing with UnitRange:
```julia
@giac_several_vars psi 0:2
# Creates: psi0, psi1, psi2 and returns (psi0, psi1, psi2)
```

2D with custom ranges:
```julia
@giac_several_vars T 0:1 0:2
# Creates: T00, T01, T02, T10, T11, T12
```

Negative indices:
```julia
@giac_several_vars c -1:1
# Creates: c_m1, c_0, c_1 (m = minus, to avoid GIAC parsing issues)
```

StepRange:
```julia
@giac_several_vars q 0:2:4
# Creates: q0, q2, q4
```

Mixed arguments (integer and range):
```julia
@giac_several_vars mixed 2 0:1
# First dim: 1:2, second dim: 0:1
# Creates: mixed10, mixed11, mixed20, mixed21
```

Edge cases:
```julia
@giac_several_vars x 0     # Returns empty tuple ()
@giac_several_vars y 1     # Creates y1, returns (y1,)
@giac_several_vars z 2 0   # Returns empty tuple (0 in any dim)
@giac_several_vars e 5:4   # Returns empty tuple (empty range)
```

# See also
- [`@giac_var`](@ref): For creating single symbolic variables
- [`giac_eval`](@ref): For evaluating string expressions
"""
macro giac_several_vars(base, dims...)
    # Validate base name is a symbol
    if !(base isa Symbol)
        throw(ArgumentError("First argument must be a symbol (base name), got $(typeof(base)): $base"))
    end

    # Validate at least one dimension is provided
    if isempty(dims)
        throw(ArgumentError("At least one dimension required"))
    end

    # Validate all dimensions are integers or range expressions, and convert to ranges
    ranges_list = []
    for d in dims
        if d isa Integer
            # Integer: validate non-negative
            if d < 0
                throw(ArgumentError("Dimensions must be non-negative, got $d"))
            end
            push!(ranges_list, 1:d)
        elseif _is_range_expr(d)
            # Range expression: evaluate at macro expansion time
            push!(ranges_list, _eval_dim_to_range(d))
        else
            throw(ArgumentError("Dimensions must be integer literals or range expressions, got $(typeof(d)): $d"))
        end
    end

    # If any range is empty, generate no variables, return empty tuple
    if any(isempty, ranges_list)
        return :(())
    end

    # Determine if we need underscore separators
    needs_sep = _needs_separator_for_macro_ranges(ranges_list)

    # Generate all index combinations using Iterators.product
    # Reverse ranges so that Iterators.product gives row-major order (last dim varies fastest)
    # Then reverse each tuple back to original dimension order
    ranges = reverse(ranges_list)
    index_combinations = (reverse(t) for t in Iterators.product(ranges...))

    # Generate assignment expressions for each variable
    exprs = Expr[]
    varnames = Symbol[]
    for indices in index_combinations
        varname = _format_indices(base, indices, needs_sep)
        push!(varnames, varname)
        push!(exprs, :($(esc(varname)) = giac_eval($(string(varname)))))
    end
    # Return tuple of created variables
    result = Expr(:tuple, [esc(v) for v in varnames]...)
    return Expr(:block, exprs..., result)
end


# Helper functions for @giac_var function syntax

#=
"""
    _build_function_string(funcname::Symbol, args::Vector{Symbol}) -> String

Build a GIAC-compatible string representation of a function call.
E.g., `_build_function_string(:u, [:t])` returns `"u(t)"`.
"""
function _build_function_string(funcname::Symbol, args::Vector{Symbol})
    return string(funcname, "(", join(string.(args), ","), ")")
end

"""
    _process_giac_var_arg(arg) -> Tuple{Symbol, String}

Process a single argument to @giac_var macro.
Returns (varname, giac_string) where:
- varname is the Julia variable name to bind
- giac_string is the GIAC expression string

For symbols: returns (sym, string(sym))
For function calls: returns (funcname, "funcname(arg1,arg2,...)")

Throws ArgumentError for invalid inputs.
"""
function _process_giac_var_arg(arg)
    if arg isa Symbol
        # Simple variable: x -> ("x", x)
        return (arg, string(arg))
    elseif arg isa Expr && arg.head == :call
        # Function call: u(t) -> ("u(t)", u)
        funcname = arg.args[1]
        funcargs = arg.args[2:end]

        # Validate function name is a symbol
        if !(funcname isa Symbol)
            throw(ArgumentError("Function name must be a symbol, got $(typeof(funcname)): $funcname"))
        end

        # Validate at least one argument
        if isempty(funcargs)
            throw(ArgumentError("Function syntax requires at least one argument: @giac_var $(funcname)() is invalid. Use @giac_var $funcname for a simple variable."))
        end

        # Validate all arguments are symbols
        for (i, farg) in enumerate(funcargs)
            if !(farg isa Symbol)
                throw(ArgumentError("Function arguments must be symbols, got $(typeof(farg)): $farg in position $i"))
            end
        end

        giac_string = _build_function_string(funcname, Symbol.(funcargs))
        return (funcname, giac_string)
    else
        if arg isa String
            throw(ArgumentError("@giac_var arguments must be symbols, not strings. Use giac_eval(\"$arg\") instead."))
        else
            throw(ArgumentError("@giac_var arguments must be symbols or function calls, got $(typeof(arg)): $arg"))
        end
    end
end
=#

#=
"""
    @giac_var sym...
    @giac_var func(args...)

Create symbolic variables or function expressions from Julia symbols.

Creates `GiacExpr` variables in the calling scope by internally calling
`giac_eval` with the stringified expression. This provides a cleaner
syntax for variable declaration similar to `@variables` in Symbolics.jl.

# Arguments

- `sym...`: Symbol names to create as simple variables
- `func(args...)`: Function syntax to create function expressions

# Examples

Single variable:
```julia
@giac_var x           # Creates x as a GiacExpr
string(x)             # "x"
x isa GiacExpr        # true
```

Multiple variables:
```julia
@giac_var x y z       # Creates x, y, z as GiacExpr variables
```

Single-variable function (NEW):
```julia
@giac_var u(t)        # Creates u as GiacExpr representing "u(t)"
string(u)             # "u(t)"

# Use with differentiation
@giac_var t
diff(u, t)            # Returns diff(u(t),t)
```

Multi-variable function (NEW):
```julia
@giac_var f(x, y)     # Creates f as GiacExpr representing "f(x,y)"
string(f)             # "f(x,y)"
```

Mixed declarations (NEW):
```julia
@giac_var t x y u(t) f(x, y)
# Creates: t, x, y as simple variables
#          u as "u(t)", f as "f(x,y)"
```

# Usage
```julia
using Giac

@giac_var x y
expr = giac_eval("x^2 + y^2")
result = giac_diff(expr, x)  # 2*x

# For ODEs
@giac_var t u(t)
# u''(t) + u(t) = 0

# Callable syntax for initial conditions (034-callable-giacexpr)
@giac_var t u(t) tau U0
u(0)                    # Returns GiacExpr: "u(0)"
u(0) ~ 1                # Initial condition: u(0) = 1
diff(u, t)(0) ~ 0       # Derivative condition: u'(0) = 0
desolve([tau * diff(u, t) + u ~ U0, u(0) ~ 1], u)
```

# See also
- [`giac_eval`](@ref): For evaluating string expressions
"""
=#
#=
macro giac_var(args...)
    # Validate at least one argument
    if isempty(args)
        throw(ArgumentError("@giac_var requires at least one argument"))
    end

    # Process each argument using helper function
    processed = [_process_giac_var_arg(arg) for arg in args]

    # Generate assignment expressions: varname = giac_eval(giac_string)
    exprs = [:($(esc(varname)) = giac_eval($giac_string)) for (varname, giac_string) in processed]

    # Return tuple of created variables
    varnames = [p[1] for p in processed]
    result = Expr(:tuple, [esc(v) for v in varnames]...)

    return Expr(:block, exprs..., result)
end
=#
