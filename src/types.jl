# Types for Giac.jl
# Core type definitions for wrapping GIAC expressions

"""
    GiacError <: Exception

Exception type for errors from the GIAC library.

# Fields
- `msg::String`: Error message
- `category::Symbol`: Error category (`:parse`, `:eval`, `:type`, `:memory`)

# Example
```julia
throw(GiacError("Failed to parse expression", :parse))
```
"""
struct GiacError <: Exception
    msg::String
    category::Symbol

    function GiacError(msg::String, category::Symbol=:eval)
        valid_categories = (:parse, :eval, :type, :memory)
        if category ∉ valid_categories
            category = :eval
        end
        new(msg, category)
    end
end

function Base.showerror(io::IO, e::GiacError)
    print(io, "GiacError(", e.category, "): ", e.msg)
end

"""
    GiacExpr

Represents a symbolic mathematical expression from GIAC.

Wraps a pointer to a C++ giac::gen object. Memory is managed automatically
via Julia's garbage collector and finalizers.

# Example
```julia
expr = giac_eval("x^2 + 1")
println(expr)  # x^2+1
```
"""
mutable struct GiacExpr
    ptr::Ptr{Cvoid}

    function GiacExpr(ptr::Ptr{Cvoid})
        obj = new(ptr)
        if ptr != C_NULL
            finalizer(_finalize_giacexpr, obj)
        end
        return obj
    end
end
GiacExpr(x::GiacExpr) = x

"""
    _finalize_giacexpr(expr::GiacExpr)

Cleanup function for GiacExpr. Called by the garbage collector.
"""
function _finalize_giacexpr(expr::GiacExpr)
    if expr.ptr != C_NULL
        _giac_free_expr(expr.ptr)
        expr.ptr = C_NULL
    end
    nothing
end

# String conversion for GiacExpr
function Base.string(expr::GiacExpr)::String
    if expr.ptr == C_NULL
        return "<null GiacExpr>"
    end
    return _giac_expr_to_string(expr.ptr)
end

function Base.show(io::IO, expr::GiacExpr)
    print(io, string(expr))
end

function Base.show(io::IO, ::MIME"text/plain", expr::GiacExpr)
    print(io, "GiacExpr: ", string(expr))
end

# ============================================================================
# GiacInput Type Alias (022-julia-type-conversion)
# ============================================================================

"""
    GiacInput

Union type representing all valid input types for GIAC command functions.

This type alias enables generated GIAC command functions to accept native Julia
types in addition to `GiacExpr`, providing a more ergonomic API.

# Supported Types
- `GiacExpr`: Native GIAC expressions
- `Number`: All Julia numeric types (Integer, AbstractFloat, Rational, Complex, etc.)
- `String`: String representations of GIAC expressions
- `Symbol`: Variable names (e.g., `:x`, `:y`)
- `AbstractVector`: Julia vectors/arrays (converted to GIAC list syntax)

# Examples
```julia
using Giac
using Giac.Commands

# All of these work:
ifactor(1000)           # Integer
ifactor(giac_eval("1000"))  # GiacExpr
simplify("x^2 - 1")     # String

# Vectors work directly (032-vector-input-solve):
@giac x y
solve([x+y~0, x-y~2], [x,y])  # System of equations
det([[1,2],[3,4]])            # Nested vectors for matrices
```

# See also
- [`GiacExpr`](@ref): The primary GIAC expression type
- [`invoke_cmd`](@ref): Universal command invocation
"""
const GiacInput = Union{GiacExpr, Number, String, Symbol, AbstractVector}

# ============================================================================
# Method Syntax Support (003-giac-commands)
# ============================================================================

"""
    Base.getproperty(expr::GiacExpr, name::Symbol)

Enable method-style syntax for GIAC commands on GiacExpr objects.

Allows calling GIAC commands as methods: `expr.factor()` is equivalent to
`giac_cmd(:factor, expr)`.

# Behavior
- If `name` is a struct field (`:ptr`), returns the field value
- Otherwise, returns a closure that invokes `giac_cmd(name, expr, args...)`

# Examples
```julia
expr = giac_eval("x^2 - 1")
x = giac_eval("x")

# Method syntax (equivalent to giac_cmd calls)
result = expr.factor()           # Same as giac_cmd(:factor, expr)
deriv = expr.diff(x)             # Same as giac_cmd(:diff, expr, x)

# Chaining
result = expr.expand().simplify().factor()
```

# See also
- `giac_cmd`: Direct command invocation
"""
function Base.getproperty(expr::GiacExpr, name::Symbol)
    # Handle struct field access
    if name === :ptr
        return getfield(expr, :ptr)
    end

    # Return a closure that invokes giac_cmd with this expression as first argument
    return (args...) -> giac_cmd(name, expr, args...)
end

"""
    Base.propertynames(expr::GiacExpr)

Return property names for GiacExpr. Includes struct fields only.
GIAC commands are accessed dynamically via getproperty.
"""
function Base.propertynames(::GiacExpr, ::Bool=false)
    return (:ptr,)
end

# ============================================================================
# Callable GiacExpr (034-callable-giacexpr)
# ============================================================================

# Note: _arg_to_giac_string is defined in command_utils.jl and used here.
# It converts Julia arguments to GIAC-compatible string representations.

"""
    _extract_function_name(expr_str::String) -> Union{String, Nothing}

Extract the function name from a simple function call expression.

For expressions like "u(t)" or "f(x,y)", returns the function name ("u" or "f").
For complex expressions or non-function-call expressions, returns nothing.

This is used by the callable GiacExpr to enable `u(0)` to produce "u(0)"
instead of "u(t)(0)" when `u` was created via `@giac_var u(t)`.

# Examples
```julia
_extract_function_name("u(t)")      # "u"
_extract_function_name("f(x,y)")    # "f"
_extract_function_name("x")         # nothing (not a function call)
_extract_function_name("diff(u,t)") # nothing (complex expression)
_extract_function_name("a+b")       # nothing (not a function call)
```
"""
function _extract_function_name(expr_str::String)
    # Match simple function call pattern: identifier followed by (...)
    # Must be a simple identifier (letters, digits, underscore) not containing operators
    m = match(r"^([a-zA-Z_][a-zA-Z0-9_]*)\(.*\)$", expr_str)
    if m !== nothing
        funcname = m.captures[1]
        # Exclude known GIAC functions that should NOT be extracted
        # (e.g., diff, integrate, etc. - these are operations, not user functions)
        giac_operations = Set(["diff", "integrate", "limit", "sum", "product",
                               "solve", "desolve", "simplify", "factor", "expand",
                               "sin", "cos", "tan", "exp", "log", "sqrt", "abs"])
        if funcname ∉ giac_operations
            return funcname
        end
    end
    return nothing
end

"""
    (expr::GiacExpr)(args...)

Make GiacExpr callable (functor) for function evaluation syntax.

This enables natural mathematical notation like `u(0)` for evaluating
a function at a point, which is essential for ODE initial conditions.

# Examples
```julia
# Basic function evaluation
@giac_var u(t)
u(0)           # Returns GiacExpr: "u(0)"
u(1)           # Returns GiacExpr: "u(1)"

# ODE initial conditions
@giac_var t u(t) tau U0
ode = tau * diff(u, t) + u ~ U0
initial = u(0) ~ 1
desolve([ode, initial], u)

# Derivative initial conditions
@giac_var t u(t)
diff(u, t)(0) ~ 1      # u'(0) = 1
diff(u, t, 2)(0) ~ 0   # u''(0) = 0

# Multi-variable functions
@giac_var f(x, y)
f(0, 0)        # Returns GiacExpr: "f(0,0)"
f(1, 2)        # Returns GiacExpr: "f(1,2)"

# With symbolic arguments
@giac_var a b
f(a, b)        # Returns GiacExpr: "f(a,b)"
```

# Arguments
- `args...`: Arguments to pass to the function. Each argument must be a
  `GiacExpr`, `Number`, or `Symbol`.

# Returns
- `GiacExpr`: A new expression representing the function call

# Throws
- `GiacError`: If the GiacExpr has a null pointer
- `ArgumentError`: If any argument has an unsupported type

# See also
- [`@giac_var`](@ref): For declaring function variables like `u(t)`
- [`diff`](@ref): For creating derivatives that can be evaluated at points
"""
function (expr::GiacExpr)(args...)
    if expr.ptr == C_NULL
        throw(GiacError("Cannot call null GiacExpr", :eval))
    end

    # Get the expression string (e.g., "u" or "u(t)" or "diff(u(t),t)")
    expr_str = string(expr)

    # For simple function expressions like "u(t)", extract the function name "u"
    # so that u(0) produces "u(0)" instead of "u(t)(0)"
    funcname = _extract_function_name(expr_str)
    base_str = funcname !== nothing ? funcname : expr_str

    # Convert arguments to GIAC format
    arg_strs = [_arg_to_giac_string(arg) for arg in args]

    # Build function call string: "base_str(arg1,arg2,...)"
    call_str = base_str * "(" * join(arg_strs, ",") * ")"

    return giac_eval(call_str)
end

"""
    (expr::GiacExpr)(first_pair::Pair{<:GiacExpr}, rest::Pair{<:GiacExpr}...) -> GiacExpr

Call-syntax sugar for [`substitute`](@ref): when a `GiacExpr` is called with
one or more `Pair{<:GiacExpr}` arguments, it dispatches to
`substitute(expr, first_pair, rest...)` and inherits its simultaneous
substitution semantics (so `expr(x => y, y => x)` swaps `x` and `y`).

The signature requires at least one pair so that zero-argument calls (`u()`)
continue to mean function evaluation, not substitution.

Idea contributed by @jverzani in pull request #11.

# Examples
```jldoctest
julia> @giac_var x y;

julia> (x^2 + 1)(x => 3)
GiacExpr: 10

julia> (x + 2*y)(x => y, y => x)
GiacExpr: y+2*x
```

# See also
- [`substitute`](@ref): the underlying operation
"""
(expr::GiacExpr)(first_pair::Pair{<:GiacExpr}, rest::Pair{<:GiacExpr}...)::GiacExpr =
    substitute(expr, first_pair, rest...)

# ============================================================================
# Derivative Operator D (035-derivative-operator)
# ============================================================================

"""
    _parse_function_expr(expr_str::String) -> Union{Tuple{String, String}, Nothing}

Parse a function expression to extract the function name and first variable.

For expressions like "u(t)" returns ("u", "t").
For expressions like "f(x,y)" returns ("f", "x").
For non-function expressions, returns nothing.

# Examples
```julia
_parse_function_expr("u(t)")     # ("u", "t")
_parse_function_expr("f(x,y)")   # ("f", "x")
_parse_function_expr("x")        # nothing
```
"""
function _parse_function_expr(expr_str::String)
    # \p{L}/\p{N}: GIAC accepts Unicode identifiers (ϕ, 𝑧, α, …);
    # ASCII-only [a-zA-Z] would reject them.
    m = match(r"^([\p{L}_][\p{L}\p{N}_]*)\(([^)]+)\)$", expr_str)
    if m !== nothing
        funcname = m.captures[1]
        args_str = m.captures[2]
        # Get first variable (strip whitespace)
        varname = strip(split(args_str, ",")[1])
        # Exclude GIAC operations
        giac_operations = Set(["diff", "integrate", "limit", "sum", "product",
                               "solve", "desolve", "simplify", "factor", "expand",
                               "sin", "cos", "tan", "exp", "log", "sqrt", "abs"])
        if funcname ∉ giac_operations
            return (funcname, String(varname))
        end
    end
    return nothing
end

"""
    DerivativeExpr

Represents a derivative expression for use in ODE initial conditions.

This type enables the `D` operator syntax following SciML conventions:
- `D(u)` represents the first derivative u'
- `D(D(u))` or `D(u, 2)` represents the second derivative u''
- `D(u)(0)` produces "u'(0)" for GIAC initial conditions

# Fields
- `base_expr::GiacExpr`: The original function expression (e.g., u(t))
- `funcname::String`: The function name (e.g., "u")
- `varname::String`: The differentiation variable (e.g., "t")
- `order::Int`: The derivative order (1 for first derivative, 2 for second, etc.)

# Example
```julia
@giac_var t u(t)

# Create derivative expressions
du = D(u)           # First derivative
d2u = D(D(u))       # Second derivative
d2u = D(u, 2)       # Alternative syntax

# Use in initial conditions
D(u)(0) ~ 1         # u'(0) = 1
D(u, 2)(0) ~ 0      # u''(0) = 0

# Use in ODEs (converts to diff notation)
ode = D(D(u)) + u ~ 0   # Equivalent to diff(u,t,2) + u = 0
```

# See also
- [`D`](@ref): The derivative operator function
- [`@giac_var`](@ref): For creating function variables
"""
struct DerivativeExpr
    base_expr::GiacExpr
    funcname::String
    varname::String
    order::Int
end

"""
    D(expr::GiacExpr) -> DerivativeExpr
    D(expr::GiacExpr, n::Int) -> DerivativeExpr
    D(d::DerivativeExpr) -> DerivativeExpr

Derivative operator following SciML/ModelingToolkit conventions.

Creates a `DerivativeExpr` that can be:
- Used in ODEs: `D(D(u)) + u ~ 0` (converts to diff notation)
- Called for initial conditions: `D(u)(0) ~ 1` (produces prime notation u'(0)=1)

# Arguments
- `expr::GiacExpr`: A function expression created with `@giac_var u(t)`
- `n::Int`: Optional derivative order (default: 1)
- `d::DerivativeExpr`: A derivative expression to differentiate further

# Examples
```julia
using Giac
using Giac.Commands: desolve

@giac_var t u(t)

# First derivative
D(u)              # Represents u'

# Second derivative (two ways)
D(D(u))           # Chain D operators
D(u, 2)           # Specify order directly

# ODE with initial conditions
ode = D(D(u)) + u ~ 0       # u'' + u = 0
u0 = u(0) ~ 1               # u(0) = 1
du0 = D(u)(0) ~ 0           # u'(0) = 0

desolve([ode, u0, du0], t, u)  # Returns: cos(t)

# Third order example
@giac_var t y(t)
ode = D(y, 3) - y ~ 0          # y''' - y = 0
desolve([ode, y(0) ~ 1, D(y)(0) ~ 1, D(y,2)(0) ~ 1], t, y)
```

# See also
- [`DerivativeExpr`](@ref): The derivative expression type
- `desolve`: Solving differential equations (via `Giac.Commands`)
"""
function D(expr::GiacExpr)
    parsed = _parse_function_expr(string(expr))
    if parsed === nothing
        throw(ArgumentError("D() requires a function expression like u(t), got: $(string(expr))"))
    end
    funcname, varname = parsed
    return DerivativeExpr(expr, funcname, varname, 1)
end

function D(expr::GiacExpr, n::Int)
    if n < 1
        throw(ArgumentError("Derivative order must be positive, got: $n"))
    end
    parsed = _parse_function_expr(string(expr))
    if parsed === nothing
        throw(ArgumentError("D() requires a function expression like u(t), got: $(string(expr))"))
    end
    funcname, varname = parsed
    return DerivativeExpr(expr, funcname, varname, n)
end

function D(d::DerivativeExpr)
    return DerivativeExpr(d.base_expr, d.funcname, d.varname, d.order + 1)
end

function D(d::DerivativeExpr, n::Int)
    if n < 1
        throw(ArgumentError("Derivative order must be positive, got: $n"))
    end
    return DerivativeExpr(d.base_expr, d.funcname, d.varname, d.order + n)
end

# String conversion - produces diff notation for use in equations
function Base.string(d::DerivativeExpr)
    if d.order == 1
        return "diff($(string(d.base_expr)),$(d.varname))"
    else
        return "diff($(string(d.base_expr)),$(d.varname),$(d.order))"
    end
end

function Base.show(io::IO, d::DerivativeExpr)
    primes = repeat("'", d.order)
    print(io, "D: ", d.funcname, primes, "(", d.varname, ")")
end

# ============================================================================
# DerivativePoint - for initial conditions (035-derivative-operator)
# ============================================================================

"""
    DerivativePoint

Represents a derivative evaluated at a specific point, for use in ODE initial conditions.

This type is created when calling a `DerivativeExpr` with arguments, e.g., `D(u)(0)`.
It delays evaluation until used with the `~` operator to create an equation,
because GIAC interprets prime notation differently in isolation vs. within desolve.

# Fields
- `funcname::String`: The function name (e.g., "u")
- `order::Int`: The derivative order
- `point_args::Vector{String}`: The point arguments as strings

# Example
```julia
@giac_var t u(t)
dp = D(u)(0)          # Returns DerivativePoint, not GiacExpr
eq = D(u)(0) ~ 1      # Creates equation: "u'(0)=1"
```
"""
struct DerivativePoint
    funcname::String
    order::Int
    point_args::Vector{String}
end

function Base.string(dp::DerivativePoint)
    primes = repeat("'", dp.order)
    return dp.funcname * primes * "(" * join(dp.point_args, ",") * ")"
end

function Base.show(io::IO, dp::DerivativePoint)
    print(io, string(dp))
end

# Callable - produces DerivativePoint for initial conditions
"""
    (d::DerivativeExpr)(args...) -> DerivativePoint

Create a derivative point expression for use in ODE initial conditions.

Returns a `DerivativePoint` that produces prime notation (u'(0), u''(0), etc.)
when used with the `~` operator.

# Example
```julia
@giac_var t u(t)
D(u)(0)           # Returns DerivativePoint representing u'(0)
D(u)(0) ~ 1       # Creates GiacExpr: "u'(0)=1"
D(u, 2)(0) ~ 0    # Creates GiacExpr: "u''(0)=0"
```
"""
function (d::DerivativeExpr)(args...)
    arg_strs = [_arg_to_giac_string(arg) for arg in args]
    return DerivativePoint(d.funcname, d.order, arg_strs)
end

"""
    DerivativeCondition

Represents an unevaluated derivative initial condition for ODEs.

This type holds the string representation of a derivative condition (e.g., "u'(0)=1")
without evaluating it through GIAC. When passed to `desolve` in an array, it gets
converted to its string form, which GIAC interprets correctly.

# Example
```julia
@giac_var t u(t)
dc = D(u)(0) ~ 1     # Returns DerivativeCondition: "u'(0)=1"

# Pass to desolve - the string is used directly
desolve([D(D(u)) + u ~ 0, u(0) ~ 1, D(u)(0) ~ 0], t, u)
```
"""
struct DerivativeCondition
    condition_str::String
end

function Base.string(dc::DerivativeCondition)
    return dc.condition_str
end

function Base.show(io::IO, dc::DerivativeCondition)
    print(io, "DerivativeCondition: ", dc.condition_str)
end

# Equation operator for DerivativePoint - produces DerivativeCondition (unevaluated)
function Base.:~(dp::DerivativePoint, value)
    value_str = _arg_to_giac_string(value)
    eq_str = string(dp) * "=" * value_str
    return DerivativeCondition(eq_str)
end

# Convert to GiacExpr for arithmetic operations
function _to_giac_expr(d::DerivativeExpr)
    return giac_eval(string(d))
end

# Arithmetic operators - convert to GiacExpr using diff notation
Base.:+(d::DerivativeExpr, other) = _to_giac_expr(d) + other
Base.:+(other, d::DerivativeExpr) = other + _to_giac_expr(d)
Base.:+(d1::DerivativeExpr, d2::DerivativeExpr) = _to_giac_expr(d1) + _to_giac_expr(d2)

Base.:-(d::DerivativeExpr, other) = _to_giac_expr(d) - other
Base.:-(other, d::DerivativeExpr) = other - _to_giac_expr(d)
Base.:-(d1::DerivativeExpr, d2::DerivativeExpr) = _to_giac_expr(d1) - _to_giac_expr(d2)
Base.:-(d::DerivativeExpr) = -_to_giac_expr(d)

Base.:*(d::DerivativeExpr, other) = _to_giac_expr(d) * other
Base.:*(other, d::DerivativeExpr) = other * _to_giac_expr(d)
Base.:*(d1::DerivativeExpr, d2::DerivativeExpr) = _to_giac_expr(d1) * _to_giac_expr(d2)

Base.:/(d::DerivativeExpr, other) = _to_giac_expr(d) / other
Base.:/(other, d::DerivativeExpr) = other / _to_giac_expr(d)
Base.:/(d1::DerivativeExpr, d2::DerivativeExpr) = _to_giac_expr(d1) / _to_giac_expr(d2)

Base.:^(d::DerivativeExpr, n) = _to_giac_expr(d) ^ n

# Equation operator ~ for ODEs and initial conditions
Base.:~(d::DerivativeExpr, other) = _to_giac_expr(d) ~ other

"""
    GiacContext

Represents a GIAC evaluation context.

Manages configuration settings, variable bindings, and computation state.
Thread-safe via internal locking.

# Example
```julia
ctx = GiacContext()
result = giac_eval("x + 1", ctx)
```
"""
mutable struct GiacContext
    ptr::Ptr{Cvoid}
    lock::ReentrantLock

    """
        GiacContext()

    An evaluation context that owns its own `giac::context`. Variable
    bindings made through it are visible only through it — not from another
    `GiacContext`, and not from the default.
    """
    function GiacContext()
        obj = new(_new_giac_context(), ReentrantLock())
        finalizer(_finalize_giaccontext, obj)
        return obj
    end

    # The process-wide context, for `DEFAULT_CONTEXT` and for every path that
    # does not name one. Kept distinct because the tier-1, introspection and
    # conversion helpers re-parse printed expressions there; see the note in
    # wrapper.jl. Not finalized — there is nothing of ours to release.
    function GiacContext(::Val{:shared})
        return new(_SHARED_CONTEXT_PTR, ReentrantLock())
    end

    # Internal constructor for existing pointer
    function GiacContext(ptr::Ptr{Cvoid})
        if ptr == C_NULL
            throw(GiacError("Cannot create GiacContext from null pointer", :type))
        end
        obj = new(ptr, ReentrantLock())
        finalizer(_finalize_giaccontext, obj)
        return obj
    end
end

"""
    _finalize_giaccontext(ctx::GiacContext)

Cleanup function for GiacContext. Called by the garbage collector.
"""
function _finalize_giaccontext(ctx::GiacContext)
    if ctx.ptr != C_NULL
        _giac_free_context(ctx.ptr)
        ctx.ptr = C_NULL
    end
    nothing
end

"""
    GiacMatrix

Represents a symbolic matrix with GiacExpr elements.

# Fields
- `ptr::Ptr{Cvoid}`: Pointer to GIAC matrix object
- `rows::Int`: Number of rows
- `cols::Int`: Number of columns

# Example
```julia
A = GiacMatrix([[a, b], [c, d]])
det(A)  # a*d - b*c
```
"""
mutable struct GiacMatrix
    ptr::Ptr{Cvoid}
    rows::Int
    cols::Int
    _source::Union{GiacExpr, Nothing}  # Keep reference to prevent GC of source

    function GiacMatrix(ptr::Ptr{Cvoid}, rows::Int, cols::Int, source::Union{GiacExpr, Nothing}=nothing)
        if rows <= 0 || cols <= 0
            throw(ArgumentError("Matrix dimensions must be positive"))
        end
        obj = new(ptr, rows, cols, source)
        # Only register finalizer if we don't have a source (we own the ptr)
        if ptr != C_NULL && source === nothing
            finalizer(_finalize_giacmatrix, obj)
        end
        return obj
    end
end

"""
    GiacMatrix(expr::GiacExpr)

Construct a GiacMatrix from a GiacExpr representing a matrix.

The GiacExpr should be a vector of vectors, e.g., from `giac_eval("[[1,2],[3,4]]")`.

# Example
```julia
expr = giac_eval("[[1,2,3],[4,5,6]]")
m = GiacMatrix(expr)  # 2×3 matrix
```
"""
function GiacMatrix(expr::GiacExpr)
    # Get string representation and parse dimensions
    expr_str = string(expr)

    # Validate it looks like a matrix [[...],[...],...]
    if !startswith(expr_str, "[") || !endswith(expr_str, "]")
        throw(ArgumentError("Expression is not a matrix: $expr_str"))
    end

    # Parse matrix structure to get dimensions
    # Count rows by counting top-level comma-separated elements
    inner = expr_str[2:end-1]
    if isempty(inner)
        throw(ArgumentError("Empty matrix expression"))
    end

    # Split into rows
    rows_strs = _split_matrix_rows(inner)
    nrows = length(rows_strs)
    if nrows == 0
        throw(ArgumentError("Matrix has no rows"))
    end

    # Get column count from first row
    first_row = rows_strs[1]
    if startswith(first_row, "[") && endswith(first_row, "]")
        first_row_inner = first_row[2:end-1]
        ncols = _count_vector_elements(first_row_inner)
    else
        # Single element row
        ncols = 1
    end

    if ncols == 0
        throw(ArgumentError("Matrix has no columns"))
    end

    # Use the expression's pointer directly, keeping reference to prevent GC
    return GiacMatrix(expr.ptr, nrows, ncols, expr)
end

"""
    GiacMatrix(exprs::Vector{GiacExpr})

Construct a GiacMatrix from a vector of GiacExpr.

If each element is a vector (row), creates a matrix with those rows.
If each element is a scalar, creates a column vector (n×1 matrix).

# Example
```julia
# Row vectors create a matrix
row1 = giac_eval("[1, 2, 3]")
row2 = giac_eval("[4, 5, 6]")
m = GiacMatrix([row1, row2])  # 2×3 matrix

# Scalars create a column vector
@giac_var x
v = GiacMatrix([x, 2*x, x^2])  # 3×1 column vector
```
"""
function GiacMatrix(exprs::Vector{GiacExpr})
    if isempty(exprs)
        throw(ArgumentError("Cannot create matrix from empty vector"))
    end

    nrows = length(exprs)

    # Get column count from first element
    first_str = string(exprs[1])
    if startswith(first_str, "[") && endswith(first_str, "]")
        # First element is a vector - use it as a row
        ncols = _count_vector_elements(first_str[2:end-1])
        # Build matrix string representation (rows are vectors)
        rows_strs = [string(e) for e in exprs]
        matrix_str = "[" * join(rows_strs, ",") * "]"
    else
        # First element is a scalar - create column vector
        # Each scalar becomes a row with 1 element: [[a],[b],[c]]
        ncols = 1
        rows_strs = ["[" * string(e) * "]" for e in exprs]
        matrix_str = "[" * join(rows_strs, ",") * "]"
    end

    # Evaluate to get proper GIAC matrix
    matrix_ptr = _giac_eval_string(matrix_str, C_NULL)

    return GiacMatrix(matrix_ptr, nrows, ncols)
end

# Helper function to split matrix string into row strings
function _split_matrix_rows(s::AbstractString)::Vector{String}
    result = String[]
    depth = 0
    current = ""
    for c in s
        if c == '['
            depth += 1
            current *= c
        elseif c == ']'
            depth -= 1
            current *= c
        elseif c == ',' && depth == 0
            push!(result, strip(current))
            current = ""
        else
            current *= c
        end
    end
    if !isempty(current)
        push!(result, strip(current))
    end
    return result
end

# Helper function to count elements in a comma-separated string
function _count_vector_elements(s::AbstractString)::Int
    if isempty(s)
        return 0
    end
    depth = 0
    count = 1
    for c in s
        if c == '[' || c == '('
            depth += 1
        elseif c == ']' || c == ')'
            depth -= 1
        elseif c == ',' && depth == 0
            count += 1
        end
    end
    return count
end

"""
    _finalize_giacmatrix(m::GiacMatrix)

Cleanup function for GiacMatrix. Called by the garbage collector.
"""
function _finalize_giacmatrix(m::GiacMatrix)
    if m.ptr != C_NULL
        _giac_free_matrix(m.ptr)
        m.ptr = C_NULL
    end
    nothing
end

# Base methods for GiacMatrix
function Base.size(m::GiacMatrix)
    return (m.rows, m.cols)
end

function Base.size(m::GiacMatrix, dim::Int)
    if dim == 1
        return m.rows
    elseif dim == 2
        return m.cols
    else
        throw(ArgumentError("Invalid dimension: $dim"))
    end
end

function Base.getindex(m::GiacMatrix, i::Int, j::Int)
    if i < 1 || i > m.rows || j < 1 || j > m.cols
        throw(BoundsError(m, (i, j)))
    end
    ptr = _giac_matrix_getindex(m.ptr, i - 1, j - 1)  # 0-indexed in C
    return GiacExpr(ptr)
end

function Base.show(io::IO, m::GiacMatrix)
    print(io, "GiacMatrix($(m.rows)×$(m.cols))")
end

# ============================================================================
# GiacMatrix to_julia Conversion (030-to-julia-bool-conversion)
# ============================================================================

"""
    to_julia(m::GiacMatrix) -> Matrix

Convert a GiacMatrix to a Julia Matrix with appropriate element type narrowing.

Boolean elements are converted to `Bool`, integers to `Int64`, etc.
The resulting matrix type is narrowed to the most specific common type.

# Example
```julia
# Integer matrix
g = giac_eval("[[1, 2], [3, 4]]")
m = GiacMatrix(g)
to_julia(m)  # 2×2 Matrix{Int64}

# Boolean matrix
g = giac_eval("[[true, false], [false, true]]")
m = GiacMatrix(g)
to_julia(m)  # 2×2 Matrix{Bool}
```

# See also
[`to_julia`](@ref), [`GiacMatrix`](@ref)
"""
function to_julia(m::GiacMatrix)
    # First: check if ALL elements can be fully converted
    all_convertible = true
    for i in 1:m.rows
        for j in 1:m.cols
            if !_can_convert_fully(m[i, j])
                all_convertible = false
                break
            end
        end
        !all_convertible && break
    end

    if all_convertible
        # Convert each element to Julia types
        result = Matrix{Any}(undef, m.rows, m.cols)
        for i in 1:m.rows
            for j in 1:m.cols
                result[i, j] = to_julia(m[i, j])
            end
        end
        # Narrow the element type
        return _narrow_matrix_type(result)
    else
        # At least one element is symbolic - keep all as GiacExpr
        result = Matrix{GiacExpr}(undef, m.rows, m.cols)
        for i in 1:m.rows
            for j in 1:m.cols
                result[i, j] = m[i, j]
            end
        end
        return result
    end
end

"""
    _narrow_matrix_type(elements::Matrix{Any}) -> Matrix

Narrow a Matrix{Any} to the most specific element type.

For homogeneous matrices, returns a typed matrix.
For mixed numeric types, promotes to common numeric type.
For matrices containing non-numeric types, returns Matrix{Any}.
"""
function _narrow_matrix_type(elements::Matrix{Any})
    if isempty(elements)
        return elements
    end

    types = unique(typeof.(elements))

    if length(types) == 1
        # Homogeneous type
        T = types[1]
        return convert(Matrix{T}, elements)
    elseif all(T -> T <: Number, types)
        # Mixed numeric types - promote
        T = reduce(promote_type, types)
        return convert(Matrix{T}, elements)
    else
        # Mixed types including non-numeric
        return elements
    end
end

# ============================================================================
# GiacMatrix Display Improvement (011-giacmatrix-display)
# ============================================================================

# Display constants
const MAX_DISPLAY_ROWS = 10
const MAX_DISPLAY_COLS = 10
const MAX_ELEMENT_WIDTH = 20

"""
    _element_string(m::GiacMatrix, i::Int, j::Int)

Get string representation of matrix element at position (i, j).
Truncates long expressions with "…" if they exceed MAX_ELEMENT_WIDTH.
"""
function _element_string(m::GiacMatrix, i::Int, j::Int)
    elem = m[i, j]
    s = string(elem)
    if length(s) > MAX_ELEMENT_WIDTH
        return s[1:MAX_ELEMENT_WIDTH-1] * "…"
    end
    return s
end

"""
    _should_truncate_rows(m::GiacMatrix)

Check if matrix has more rows than can be displayed.
"""
function _should_truncate_rows(m::GiacMatrix)
    return m.rows > MAX_DISPLAY_ROWS
end

"""
    _should_truncate_cols(m::GiacMatrix)

Check if matrix has more columns than can be displayed.
"""
function _should_truncate_cols(m::GiacMatrix)
    return m.cols > MAX_DISPLAY_COLS
end

"""
    _display_row_indices(m::GiacMatrix)

Return the row indices to display. For large matrices, returns
first 5 rows, a marker (-1) for ellipsis, and last 2 rows.
"""
function _display_row_indices(m::GiacMatrix)
    if _should_truncate_rows(m)
        return [1:5; -1; (m.rows-1):m.rows]
    end
    return collect(1:m.rows)
end

"""
    _display_col_indices(m::GiacMatrix)

Return the column indices to display. For large matrices, returns
first 5 columns, a marker (-1) for ellipsis, and last 2 columns.
"""
function _display_col_indices(m::GiacMatrix)
    if _should_truncate_cols(m)
        return [1:5; -1; (m.cols-1):m.cols]
    end
    return collect(1:m.cols)
end

"""
    _compute_column_widths(m::GiacMatrix, row_indices, col_indices)

Compute the display width needed for each column.
"""
function _compute_column_widths(m::GiacMatrix, row_indices, col_indices)
    widths = zeros(Int, length(col_indices))
    for (cj, j) in enumerate(col_indices)
        if j == -1
            widths[cj] = 1  # Width for "⋯"
            continue
        end
        for i in row_indices
            if i == -1
                continue
            end
            elem_str = _element_string(m, i, j)
            widths[cj] = max(widths[cj], length(elem_str))
        end
    end
    return widths
end

"""
    Base.string(m::GiacMatrix)

Return compact string representation of GiacMatrix.
"""
function Base.string(m::GiacMatrix)
    return "GiacMatrix($(m.rows)×$(m.cols))"
end

"""
    Base.show(io::IO, ::MIME"text/plain", m::GiacMatrix)

Display GiacMatrix with dimensions header and grid of contents.
Large matrices are truncated with ellipsis indicators.
"""
function Base.show(io::IO, ::MIME"text/plain", m::GiacMatrix)
    # Print header
    println(io, "$(m.rows)×$(m.cols) GiacMatrix:")

    # Get indices to display
    row_indices = _display_row_indices(m)
    col_indices = _display_col_indices(m)

    # Compute column widths for alignment
    widths = _compute_column_widths(m, row_indices, col_indices)

    # Print matrix contents
    for (ri, i) in enumerate(row_indices)
        if i == -1
            # Print row ellipsis line
            for (cj, j) in enumerate(col_indices)
                if cj > 1
                    print(io, "  ")
                end
                if j == -1
                    print(io, lpad("⋱", widths[cj]))
                else
                    print(io, lpad("⋮", widths[cj]))
                end
            end
        else
            # Print actual row content
            for (cj, j) in enumerate(col_indices)
                if cj > 1
                    print(io, "  ")
                end
                if j == -1
                    print(io, lpad("⋯", widths[cj]))
                else
                    elem_str = _element_string(m, i, j)
                    print(io, lpad(elem_str, widths[cj]))
                end
            end
        end
        if ri < length(row_indices)
            println(io)
        end
    end
end
