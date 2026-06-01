# High-level API for Giac.jl
# User-facing functions for symbolic computation

"""
    giac_eval(expr::String, ctx::GiacContext=DEFAULT_CONTEXT[])

Evaluate a GIAC expression string and return a GiacExpr.

# Arguments
- `expr::String`: A string containing a valid GIAC expression
- `ctx::GiacContext`: Optional evaluation context (uses DEFAULT_CONTEXT if not provided)

# Returns
- `GiacExpr`: The evaluated expression

# Throws
- `GiacError(:parse)`: If the expression cannot be parsed
- `GiacError(:eval)`: If evaluation fails

# Examples
```jldoctest
julia> giac_eval("2+3")
GiacExpr: 5

julia> giac_eval("diff(x^2, x)")
GiacExpr: 2*x

julia> giac_eval("factor(x^2-1)")
GiacExpr: (x-1)*(x+1)
```
"""
function giac_eval(expr::String, ctx::GiacContext=DEFAULT_CONTEXT[])::GiacExpr
    if isempty(expr)
        throw(GiacError("Empty expression", :parse))
    end

    with_giac_lock() do
        ptr = _giac_eval_string(expr, ctx.ptr)
        if ptr == C_NULL
            throw(GiacError("Failed to evaluate expression: $expr", :eval))
        end
        return GiacExpr(ptr)
    end
end

"""
    giac_eval(expr::GiacExpr, ctx::GiacContext=DEFAULT_CONTEXT[])

Re-evaluate an existing GiacExpr in a context (useful after variable assignments).
"""
function giac_eval(expr::GiacExpr, ctx::GiacContext=DEFAULT_CONTEXT[])::GiacExpr
    # Convert to string and re-evaluate
    return giac_eval(string(expr), ctx)
end

# =============================================================================
# Note: Calculus and Algebra functions removed (Feature 021)
# =============================================================================
# The following functions have been removed in favor of Giac.Commands:
#   - giac_diff → Giac.Commands.diff or invoke_cmd(:diff, ...)
#   - giac_integrate → Giac.Commands.integrate or invoke_cmd(:integrate, ...)
#   - giac_limit → Giac.Commands.limit or invoke_cmd(:limit, ...)
#   - giac_series → Giac.Commands.series or invoke_cmd(:series, ...)
#   - giac_factor → Giac.Commands.factor or invoke_cmd(:factor, ...)
#   - giac_expand → Giac.Commands.expand or invoke_cmd(:expand, ...)
#   - giac_simplify → Giac.Commands.simplify or invoke_cmd(:simplify, ...)
#   - giac_solve → Giac.Commands.solve or invoke_cmd(:solve, ...)
#   - giac_gcd → Giac.Commands.gcd or invoke_cmd(:gcd, ...)
# =============================================================================

# =============================================================================
# Matrix Operations (Linear Algebra)
# =============================================================================

"""
    GiacMatrix(elements::AbstractMatrix)

Create a GiacMatrix from a Julia matrix.

# Example
```julia
A = GiacMatrix([1 2; 3 4])
```
"""
function GiacMatrix(elements::AbstractMatrix)
    rows, cols = size(elements)
    # Convert elements to strings for GIAC
    str_elements = ["[" * join([string(elements[i, j]) for j in 1:cols], ",") * "]" for i in 1:rows]
    matrix_str = "[" * join(str_elements, ",") * "]"

    with_giac_lock() do
        ptr = _giac_create_matrix(matrix_str, rows, cols)
        if ptr == C_NULL
            throw(GiacError("Failed to create matrix", :memory))
        end
        return GiacMatrix(ptr, rows, cols)
    end
end

"""
    GiacMatrix(elements::Vector{Vector})

Create a GiacMatrix from nested vectors.
"""
function GiacMatrix(elements::Vector{<:Vector})
    rows = length(elements)
    cols = length(elements[1])
    for row in elements
        if length(row) != cols
            throw(ArgumentError("All rows must have the same length"))
        end
    end

    matrix = [elements[i][j] for i in 1:rows, j in 1:cols]
    return GiacMatrix(matrix)
end

# iterate over a matrix
function Base.iterate(M::GiacMatrix, state=nothing)
    m, n = size(M)
    sz = m*n
    # doing computation by hand, must be a better way
    i = isnothing(state) ? 1 : state + 1
    i > sz && return nothing
    c,r = divrem(i-1, m)
    return (M[r+1, c+1], i)
end

Base.length(M::GiacMatrix) = (sz = size(M); sz[1]*sz[2])


# linear access for GiacMatrix
function Base.LinearIndices(M::GiacMatrix)
    m,n = size(M)
    Base.LinearIndices((Base.OneTo(m), Base.OneTo(n)))
end

function Base.CartesianIndices(M::GiacMatrix)
    m,n = size(M)
    Base.CartesianIndices((Base.OneTo(m), Base.OneTo(n)))
end

Base.getindex(M::GiacMatrix, i::Int) = M[Base.CartesianIndices(M)[i]]
Base.getindex(M::GiacMatrix, I::CartesianIndex) = M[I.I...]



# =============================================================================
# GiacMatrix Symbol Constructor (Feature 013)
# Extended with UnitRange support (Feature 037)
# =============================================================================

"""
    _to_range(dim::Integer) -> UnitRange{Int}
    _to_range(dim::OrdinalRange) -> OrdinalRange

Convert a dimension specification to a range.
Integer n becomes 1:n for backward compatibility.
Ranges pass through unchanged.
"""
_to_range(dim::Integer) = 1:dim
_to_range(dim::OrdinalRange) = dim

"""
    _needs_separator_for_range(range::OrdinalRange) -> Bool

Check if underscore separators are needed for the given range.
Returns true if any index is > 9 or < 0.
"""
function _needs_separator_for_range(range::OrdinalRange)
    isempty(range) && return false
    return minimum(range) < 0 || maximum(range) > 9
end

"""
    _needs_separator_for_ranges(ranges) -> Bool

Check if underscore separators are needed for a collection of ranges.
Returns true if any range has an index > 9 or < 0.
"""
function _needs_separator_for_ranges(ranges)
    for r in ranges
        if _needs_separator_for_range(r)
            return true
        end
    end
    return false
end

"""
    GiacMatrix(base::Symbol, dims::Integer...)

Create a symbolic GiacMatrix with variable elements named using the base symbol and indices.

This constructor creates a matrix populated with symbolic variables. For 1D input,
creates a column vector (n×1). For 2D input, creates a matrix (rows×cols).

# Arguments
- `base::Symbol`: Base name for the symbolic variables (e.g., `:m`, `:α`)
- `dims::Integer...`: One or two dimensions

# Naming Convention
- Dimensions ≤ 9: Indices concatenated directly (e.g., `m11`, `m23`)
- Any dimension > 9: Underscore separators used (e.g., `m_1_10`, `m_10_1`)
- 1D vectors use single index (e.g., `v1`, `v2`, `v3`)

# Examples

Create a 2×3 symbolic matrix:
```julia
M = GiacMatrix(:m, 2, 3)
# Elements: m11, m12, m13, m21, m22, m23
M[1, 2]  # m12
size(M)  # (2, 3)
```

Create a column vector:
```julia
V = GiacMatrix(:v, 3)
# Elements: v1, v2, v3
size(V)  # (3, 1)
```

Large dimensions use underscores:
```julia
M = GiacMatrix(:m, 10, 10)
M[1, 10]  # m_1_10
```

Unicode base names:
```julia
Γ = GiacMatrix(:Γ, 2, 2)
# Elements: Γ11, Γ12, Γ21, Γ22
```

# Throws
- `ArgumentError`: If no dimensions provided
- `ArgumentError`: If more than 2 dimensions provided
- `ArgumentError`: If any dimension is not positive (≤ 0)

# See also
- [`@giac_several_vars`](@ref): Macro for creating indexed symbolic variables
"""
function GiacMatrix(base::Symbol, dims::Integer...)
    # Validate dimension count
    if length(dims) == 0
        throw(ArgumentError("At least one dimension required"))
    end
    if length(dims) > 2
        throw(ArgumentError("GiacMatrix supports at most 2 dimensions. Use GiacTensor for N-dimensional arrays."))
    end

    # Validate dimension values (must be positive, GiacMatrix requires positive dimensions)
    for d in dims
        if d <= 0
            throw(ArgumentError("Dimensions must be positive, got $d"))
        end
    end

    # Handle based on number of dimensions
    if length(dims) == 1
        return _create_symbolic_vector(base, dims[1])
    else
        return _create_symbolic_matrix(base, dims[1], dims[2])
    end
end

"""
    GiacMatrix(base::Symbol, dims::Union{Integer, OrdinalRange}...)

Create a symbolic GiacMatrix with variable elements using custom index ranges.

This constructor allows non-1-based indexing for symbolic matrices. Integer arguments
are treated as 1:n for backward compatibility. UnitRange and StepRange arguments
specify custom index ranges.

# Arguments
- `base::Symbol`: Base name for the symbolic variables (e.g., `:m`, `:α`)
- `dims::Union{Integer, OrdinalRange}...`: One or two dimension specifications
  - Integer `n`: Creates indices 1:n (backward compatible)
  - UnitRange `a:b`: Creates indices from a to b
  - StepRange `a:s:b`: Creates indices from a to b with step s

# Naming Convention
- Indices 0-9: concatenated directly (e.g., `m00`, `m12`)
- Indices > 9: underscore separators (e.g., `m_1_10`)
- Negative indices: `m` prefix for minus (e.g., -1 → `m1`, so `x_m1`)

# Examples

0-based indexing:
```julia
M = GiacMatrix(:m, 0:2, 0:2)
# Elements: m00, m01, m02, m10, ..., m22
```

Negative indices:
```julia
J = GiacMatrix(:J, -1:1)
# Elements: J_m1, J_0, J_1 (m = minus)
```

Mixed integer and range:
```julia
A = GiacMatrix(:A, 3, 0:2)
# Rows use 1:3, columns use 0:2
# Elements: A10, A11, A12, A20, ..., A32
```

StepRange:
```julia
v = GiacMatrix(:v, 0:2:6)
# Elements: v0, v2, v4, v6
```

# See also
- [`@giac_several_vars`](@ref): Macro for creating indexed symbolic variables
"""
function GiacMatrix(base::Symbol, dims::Union{Integer, OrdinalRange}...)
    # Validate dimension count
    if length(dims) == 0
        throw(ArgumentError("At least one dimension required"))
    end
    if length(dims) > 2
        throw(ArgumentError("GiacMatrix supports at most 2 dimensions. Use GiacTensor for N-dimensional arrays."))
    end

    # Convert all dims to ranges
    ranges = [_to_range(d) for d in dims]

    # Validate integer dimensions (must be positive for backward compat)
    for d in dims
        if d isa Integer && d <= 0
            throw(ArgumentError("Dimensions must be positive, got $d"))
        end
    end

    # Handle based on number of dimensions
    if length(ranges) == 1
        return _create_symbolic_vector_range(base, ranges[1])
    else
        return _create_symbolic_matrix_range(base, ranges[1], ranges[2])
    end
end

"""
    _create_symbolic_vector(base::Symbol, n::Int) -> GiacMatrix

Internal helper to create an n×1 column vector with symbolic elements.
Elements are named with single index: base1, base2, ..., baseN.
"""
function _create_symbolic_vector(base::Symbol, n::Int)
    # Determine if we need underscore separators
    needs_sep = _needs_separator((n,))

    # Create elements as column vector
    elements = Matrix{GiacExpr}(undef, n, 1)
    for i in 1:n
        varname = _format_indices(base, (i,), needs_sep)
        elements[i, 1] = giac_eval(string(varname))
    end

    return GiacMatrix(elements)
end

"""
    _create_symbolic_matrix(base::Symbol, rows::Int, cols::Int) -> GiacMatrix

Internal helper to create a rows×cols matrix with symbolic elements.
Elements are named with double indices in row-major order: base11, base12, ..., baseRC.
"""
function _create_symbolic_matrix(base::Symbol, rows::Int, cols::Int)
    # Determine if we need underscore separators
    needs_sep = _needs_separator((rows, cols))

    # Create elements in row-major order
    elements = Matrix{GiacExpr}(undef, rows, cols)
    for i in 1:rows
        for j in 1:cols
            varname = _format_indices(base, (i, j), needs_sep)
            elements[i, j] = giac_eval(string(varname))
        end
    end

    return GiacMatrix(elements)
end

"""
    _create_symbolic_vector_range(base::Symbol, range::OrdinalRange) -> GiacMatrix

Internal helper to create a column vector with symbolic elements using custom index range.
Elements are named using the actual index values from the range.
"""
function _create_symbolic_vector_range(base::Symbol, range::OrdinalRange)
    n = length(range)

    # Handle empty range
    if n == 0
        elements = Matrix{GiacExpr}(undef, 0, 1)
        return GiacMatrix(elements)
    end

    # Determine if we need underscore separators
    needs_sep = _needs_separator_for_range(range)

    # Create elements as column vector
    elements = Matrix{GiacExpr}(undef, n, 1)
    for (pos, idx) in enumerate(range)
        varname = _format_indices(base, (idx,), needs_sep)
        elements[pos, 1] = giac_eval(string(varname))
    end

    return GiacMatrix(elements)
end

"""
    _create_symbolic_matrix_range(base::Symbol, row_range::OrdinalRange, col_range::OrdinalRange) -> GiacMatrix

Internal helper to create a matrix with symbolic elements using custom index ranges.
Elements are named using the actual index values from the ranges.
"""
function _create_symbolic_matrix_range(base::Symbol, row_range::OrdinalRange, col_range::OrdinalRange)
    nrows = length(row_range)
    ncols = length(col_range)

    # Handle empty ranges
    if nrows == 0 || ncols == 0
        elements = Matrix{GiacExpr}(undef, nrows, ncols)
        return GiacMatrix(elements)
    end

    # Determine if we need underscore separators
    needs_sep = _needs_separator_for_ranges([row_range, col_range])

    # Create elements in row-major order
    elements = Matrix{GiacExpr}(undef, nrows, ncols)
    for (row_pos, row_idx) in enumerate(row_range)
        for (col_pos, col_idx) in enumerate(col_range)
            varname = _format_indices(base, (row_idx, col_idx), needs_sep)
            elements[row_pos, col_pos] = giac_eval(string(varname))
        end
    end

    return GiacMatrix(elements)
end

"""
    det(m::GiacMatrix)

Compute the determinant of a matrix.
"""
function LinearAlgebra.det(m::GiacMatrix)::GiacExpr
    if m.rows != m.cols
        throw(ArgumentError("Determinant requires a square matrix"))
    end

    with_giac_lock() do
        ptr = _giac_matrix_det(m.ptr)
        if ptr == C_NULL
            throw(GiacError("Determinant computation failed", :eval))
        end
        return GiacExpr(ptr)
    end
end

"""
    inv(m::GiacMatrix)

Compute the inverse of a matrix.
"""
function Base.inv(m::GiacMatrix)::GiacMatrix
    if m.rows != m.cols
        throw(ArgumentError("Inverse requires a square matrix"))
    end

    with_giac_lock() do
        ptr = _giac_matrix_inv(m.ptr)
        if ptr == C_NULL
            throw(GiacError("Matrix inversion failed (may be singular)", :eval))
        end
        return GiacMatrix(ptr, m.rows, m.cols)
    end
end

"""
    tr(m::GiacMatrix)

Compute the trace of a matrix.
"""
function LinearAlgebra.tr(m::GiacMatrix)::GiacExpr
    if m.rows != m.cols
        throw(ArgumentError("Trace requires a square matrix"))
    end

    with_giac_lock() do
        ptr = _giac_matrix_trace(m.ptr)
        if ptr == C_NULL
            throw(GiacError("Trace computation failed", :eval))
        end
        return GiacExpr(ptr)
    end
end

"""
    transpose(m::GiacMatrix)

Compute the transpose of a matrix.
"""
function Base.transpose(m::GiacMatrix)::GiacMatrix
    with_giac_lock() do
        ptr = _giac_matrix_transpose(m.ptr)
        if ptr == C_NULL
            throw(GiacError("Transpose failed", :eval))
        end
        return GiacMatrix(ptr, m.cols, m.rows)
    end
end

"""
    norm(m::Union{GiacExpr, Vector{GiacExpr}, p=2)::GiacExpr

"""
function LinearAlgebra.norm(m::Union{T, Vector{T}}, p::Real=2) where {T <: GiacExpr}
    p == 1   && return invoke_cmd(:l1norm, m)
    p == 2   && return invoke_cmd(:l2norm, m)
    p == Inf && return invoke_cmd(:maxnorm, m)
    p > 0 || throw(ArgumentError("p not positive"))
    return sum(xᵢ^p for xᵢ ∈ m)^(1/p)
end
