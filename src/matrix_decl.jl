# @giac_matrix: matrices of symbolic entries, with a structure, properties and assumptions.
#
# The structures (symmetric, skew, diagonal, upper, lower) are ported from Kahli Burke's
# `ergonomics` branch (`giac_array(...; structure)`). The syntax is the one agreed with
# MathInterchange: `@giac_matrix P[n, n] [posdef]`, Symbolics-style metadata in brackets, and
# entries named like the arrays of `@giac_var` (`P₁_₂`). Like `@giac_var`, the macro only
# parses; sizes, ranges and bounds are evaluated where it is called.

const _MATRIX_LAYOUTS = (:symmetric, :skew, :diagonal, :upper, :lower)
const _MATRIX_PROPERTIES = (:posdef, :negdef)

# The properties declared for a matrix, keyed by the identity of the Julia matrix (not by its
# entries: an equal matrix computed later was not declared). A finalizer drops the entry when
# the matrix is collected, so the key cannot be reused; the lock is a spin lock because a
# finalizer must not yield.
const _DECLARED_MATRIX_PROPERTIES = Dict{UInt, Set{Symbol}}()
const _DECLARED_MATRIX_LOCK = Threads.SpinLock()

function _forget_matrix_properties(M)
    lock(_DECLARED_MATRIX_LOCK)
    try
        delete!(_DECLARED_MATRIX_PROPERTIES, objectid(M))
    finally
        unlock(_DECLARED_MATRIX_LOCK)
    end
end

"""
    @giac_matrix A[m, n] P[n, n] [posdef] W[3, 3] [skew] V[2, 2]::(upper, real)

Declare matrices of symbolic entries and bind them to Julia variables. Each matrix is a
`Matrix{GiacExpr}` whose entries are named like the arrays of [`@giac_var`](@ref): `A₁_₁`,
`A₁_₂`, …. The sizes may be integers (`A[2, 3]`, indices from 1) or ranges (`C[0:1, 0:1]`),
and may use variables (`B[n, n]`). Returns a tuple of the matrices.

A structure, a property and assumptions on the entries are written in brackets after the matrix
(`P[2, 2] [symmetric]`) or after `::` (`P[2, 2]::symmetric`), several of them together:

* a structure, for a square matrix:
  * `symmetric`: entry `(j, i)` is entry `(i, j)`, named with `i ≤ j`;
  * `skew`: entry `(j, i)` is minus entry `(i, j)`, the diagonal is 0;
  * `diagonal`: the entries off the diagonal are 0;
  * `upper`, `lower`: triangular, the rest 0.
* a property: `posdef` or `negdef`, a positive or negative definite matrix. It makes the matrix
  symmetric (unless it is declared `diagonal`) and its diagonal entries positive (negative), the
  consequence Giac can record, since its assumptions are on variables. The property itself is
  kept for [`Giac.matrix_properties`](@ref).
* assumptions on the free entries, as in `@giac_var`: `real`, `positive`, `>(0)`, ….

Declaring a matrix resets its entries, as `@giac_var` does.

```julia
@giac_matrix A[2, 2] P[2, 2] [posdef]
P★ = solve(P*A + A'*P ~ -I, P)       # with the linear algebra on arrays of expressions
```
"""
macro giac_matrix(xs...)
    isempty(xs) && throw(ArgumentError("@giac_matrix requires at least one matrix, e.g. @giac_matrix A[2, 2]"))
    if length(xs) == 1 && xs[1] isa Expr && xs[1].head == :tuple
        xs = xs[1].args
    end
    decls = map(_parse_matrix_decl, _merge_metadata(Any[xs...]))
    defs = map(_gen_matrix_decl, decls)
    return Expr(:block, defs..., Expr(:tuple, map(d -> esc(d.sym), decls)...))
end

function _matrix_parseerror(x)
    throw(ArgumentError("Incorrect @giac_matrix syntax at `$x`. Write a matrix as `A[m, n]`, with " *
                        "a structure, property or assumptions in brackets or after `::`, e.g. " *
                        "`@giac_matrix A[2, 2] P[2, 2] [posdef] V[2, 2]::(upper, real)`."))
end

# One declaration, as written: `A[m, n]`, `A[m, n]::spec` or `A[m, n]::(spec, ...)`.
function _parse_matrix_decl(x)
    specs = Any[]
    expr = x
    if expr isa Expr && expr.head == :(::)
        length(expr.args) == 2 || _matrix_parseerror(x)
        expr, spec = expr.args
        specs = spec isa Expr && spec.head == :tuple ? Any[spec.args...] : Any[spec]
    end
    (expr isa Expr && expr.head == :ref && expr.args[1] isa Symbol) || _matrix_parseerror(x)
    dims = expr.args[2:end]
    length(dims) == 2 || throw(ArgumentError(
        "@giac_matrix: a matrix has two dimensions, got $(length(dims)) in `$expr`; use @giac_var for other arrays"))
    layout = :general
    properties = Symbol[]
    assumptions = Any[]
    for s in specs
        if s isa Symbol && s in _MATRIX_LAYOUTS
            layout === :general || throw(ArgumentError(
                "@giac_matrix: `$(expr.args[1])` has two structures, $layout and $s"))
            layout = s
        elseif s isa Symbol && s in _MATRIX_PROPERTIES
            push!(properties, s)
        else
            push!(assumptions, try
                _parse_assumption(s)
            catch err
                err isa ArgumentError || rethrow()
                throw(ArgumentError("Unknown @giac_matrix specification `$s`. Use a structure " *
                                    "($(join(_MATRIX_LAYOUTS, ", "))), a property " *
                                    "($(join(_MATRIX_PROPERTIES, ", "))) or an assumption on the " *
                                    "entries as in @giac_var (real, positive, >(0), ...)."))
            end)
        end
    end
    :posdef in properties && :negdef in properties && throw(ArgumentError(
        "@giac_matrix: `$(expr.args[1])` cannot be both posdef and negdef"))
    return (; sym = expr.args[1], dims, layout, properties, assumptions)
end

function _gen_matrix_decl(d)
    G(f) = GlobalRef(@__MODULE__, f)
    rhs = :($(G(:_declare_matrix))($(String(d.sym)), ($(map(esc, d.dims)...),),
                                   $(QuoteNode(d.layout)), $(d.properties),
                                   $(G(:_Assumption))[$(d.assumptions...)]))
    return :($(esc(d.sym)) = $rhs)
end

# An index range from a size or a range, as written.
_matrix_range(n::Integer) = 1:n
_matrix_range(r::AbstractRange{<:Integer}) = r
_matrix_range(x) = throw(ArgumentError("@giac_matrix: a size must be an integer or an integer range, got $(repr(x))"))

# Whether entry (i, j) of a matrix with `layout` is a variable of its own.
function _free_entry(layout::Symbol, i::Integer, j::Integer)
    layout === :general && return true
    layout === :symmetric && return i <= j
    layout === :skew && return i < j
    layout === :diagonal && return i == j
    layout === :upper && return i <= j
    return i >= j                                   # :lower
end

function _declare_matrix(name::String, dims::Tuple, layout::Symbol, properties::Vector{Symbol},
                         assumptions::Vector{_Assumption})
    rows, cols = map(_matrix_range, dims)
    if !isempty(properties) && layout === :general
        layout = :symmetric                         # a definite matrix is symmetric
    end
    if layout !== :general && length(rows) != length(cols)
        throw(ArgumentError("@giac_matrix: a $layout matrix is square, `$name` is $(length(rows))×$(length(cols))"))
    end
    if !isempty(properties) && !(layout in (:symmetric, :diagonal))
        throw(ArgumentError("@giac_matrix: $(join(properties, ", ")) needs a symmetric or diagonal matrix, `$name` is $layout"))
    end
    sign = :posdef in properties ? :positive : :negdef in properties ? :negative : nothing
    entry_name(i, j) = name * map_subscripts(i) * "_" * map_subscripts(j)
    # the free entries, declared once each
    free = Dict{Tuple{Int, Int}, GiacExpr}()
    for (a, i) in enumerate(rows), (b, j) in enumerate(cols)
        _free_entry(layout, a, b) || continue
        own = a == b && sign !== nothing ? _Assumption[assumptions; _RangeAssumption(sign)] : assumptions
        free[(a, b)] = _declare_symbol(entry_name(i, j), own)
    end
    zero_ = zero(GiacExpr)
    value(a, b) = haskey(free, (a, b)) ? free[(a, b)] :
                  layout === :symmetric ? free[(b, a)] :
                  layout === :skew ? (a == b ? zero_ : -free[(b, a)]) : zero_
    M = GiacExpr[value(a, b) for a in eachindex(rows), b in eachindex(cols)]
    props = Set{Symbol}(properties)
    layout === :general || push!(props, layout)
    if !isempty(props)
        lock(_DECLARED_MATRIX_LOCK)
        try
            _DECLARED_MATRIX_PROPERTIES[objectid(M)] = props
        finally
            unlock(_DECLARED_MATRIX_LOCK)
        end
        finalizer(_forget_matrix_properties, M)
    end
    return M
end

"""
    Giac.matrix_properties(M) -> Set{Symbol}

The structure and properties `M` was declared with by [`@giac_matrix`](@ref): `:symmetric`,
`:skew`, `:diagonal`, `:upper`, `:lower`, `:posdef`, `:negdef`. Empty for any other matrix,
including one computed from a declared matrix.
"""
function matrix_properties(M::AbstractMatrix)
    lock(_DECLARED_MATRIX_LOCK)
    try
        return copy(get(_DECLARED_MATRIX_PROPERTIES, objectid(M), Set{Symbol}()))
    finally
        unlock(_DECLARED_MATRIX_LOCK)
    end
end
