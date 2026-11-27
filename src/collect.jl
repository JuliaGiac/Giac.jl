# Taylor polynomials, and grouping an expression by monomials in chosen variables.
# Ported from Kahli Burke's `ergonomics` branch (src/array_algebra.jl and the first version of
# src/collect.jl, which works on GIAC's own expressions).

"""
    taylor(f, x => a, n)
    taylor(f, [x1, x2] => (a1, a2), n)
    taylor(f, x, n)

The Taylor polynomial of `f` about `x = a` (about 0 when no point is given): every term up to
total degree `n` in the variables. `x` may be a vector of variables, with the point a vector or
a tuple (a tuple keeps exact constants, `x => (π, 0)`) or one value for all. For an array `f`,
entry by entry.

```julia
@giac_var x1 x2 u
f = [x2, -sin(x1) + u * cos(x1)]
taylor(f, [x1, x2, u] => (π, 0, 0), 1)   # [x2, x1 - π - u]: linearized about the upright position
```
"""
function taylor(f::GiacExpr, point::Pair, n::Integer)
    x, a = point
    vars = x isa GiacExpr ? GiacExpr[x] : collect(GiacExpr, x)
    at = a isa Union{AbstractArray, Tuple} ? collect(Any, a) : fill(a, length(vars))
    length(at) == length(vars) ||
        throw(DimensionMismatch("expanding about a point of $(length(at)) values in $(length(vars)) variables"))
    return invoke_cmd(:series, f, vars, at, n)
end
taylor(f::GiacExpr, x::Union{GiacExpr, AbstractVector{GiacExpr}}, n::Integer) = taylor(f, x => 0, n)
taylor(f::AbstractArray{GiacExpr}, args...) = map(e -> taylor(e, args...), f)

"""
    coefficients(e, vars) -> Dict{GiacExpr, GiacExpr}

The coefficient of each monomial in the variables `vars` (a variable or an array of them) in the
expanded `e`, as `monomial => coefficient`; the term free of `vars` is under `1`. A factor that
depends on `vars` without being a power of one (`sin(x1)`) is part of the monomial. Coefficients
are normalized, and monomials whose coefficient is zero are left out.

Not exported, as other algebra packages export a `coefficients` of their own:
`using Giac: coefficients`, or `Giac.coefficients(…)`.

```julia
@giac_var x1 x2 a b
c = Giac.coefficients(a * x1^2 + b * x1 * x2 + 2a * x1^2 + 3, [x1, x2])
c[x1^2]                  # 3*a
c[x1 * x2]               # b
c[one(GiacExpr)]         # 3
```
"""
function coefficients(e::GiacExpr, vars)
    return Dict(m => c for (m, c) in _collected(e, vars))
end

"""
    collect_terms(e, vars)

`e` as a sum over monomials in the variables `vars`, each with its coefficient collected and
normalized: `(a + 2b)*x1^2 + (a - b)*x1*x2 + …`. Higher degrees come first, and within a
degree, higher powers of the earlier variables. For an array, entry by entry. See
[`Giac.coefficients`](@ref) for the pieces.
"""
function collect_terms(e::GiacExpr, vars)
    terms = [isone(c) ? m : isone(m) ? c : c * m for (m, c) in _collected(e, vars)]
    return isempty(terms) ? zero(GiacExpr) : reduce(+, terms)
end
collect_terms(A::AbstractArray, vars) = map(e -> collect_terms(e, vars), A)

# `monomial => coefficient` pairs in graded order, zero coefficients dropped
function _collected(e::GiacExpr, vars)
    varnames = [string(v) for v in (vars isa GiacExpr ? (vars,) : vec(collect(vars)))]
    depends(f) = any(s -> string(s) in varnames, free_symbols(f))
    # key => (monomial, its order key, coefficient terms)
    groups = Dict{String, Tuple{GiacExpr, Vector{Int}, Vector{GiacExpr}}}()
    for term in _sum_terms(Commands.expand(e))
        fs = _product_factors(term)
        # powers of the variables in their order, then other factors (`sin(x1)`)
        mono = sort!(filter(depends, fs); by = f -> (_base_index(f, varnames), string(f)))
        coef = filter(!depends, fs)
        key = join(string.(mono), "*")
        m, _, cs = get!(groups, key) do
            powers = [_power(mono, v) for v in varnames]
            # total degree first, then the powers of the variables in order, all descending
            order = vcat(-sum(_degree, mono; init = 0), -powers)
            (isempty(mono) ? one(GiacExpr) : reduce(*, mono), order, GiacExpr[])
        end
        push!(cs, isempty(coef) ? one(GiacExpr) : reduce(*, coef))
    end
    out = Pair{GiacExpr, GiacExpr}[]
    for key in sort!(collect(keys(groups)); by = k -> (groups[k][2], k))
        m, _, cs = groups[key]
        c = Commands.normal(reduce(+, cs))
        iszero(c) || push!(out, m => c)
    end
    return out
end

_sum_terms(e::GiacExpr) = iscall(e) && symb_funcname(e) == "+" ? arguments(e) : [e]

function _product_factors(t::GiacExpr)
    iscall(t) || return [t]
    head = symb_funcname(t)
    head == "*" && return arguments(t)
    head == "-" && return vcat(convert(GiacExpr, -1), _product_factors(only(arguments(t))))
    return [t]
end

# the degree a factor adds to a monomial: its integer exponent, or 1
function _degree(f::GiacExpr)
    iscall(f) && symb_funcname(f) == "^" || return 1
    n = arguments(f)[2]
    return is_integer(n) ? Int(to_julia(n)) : 1
end

# the position in `varnames` of a factor's variable, if it is a variable or a power of one
function _base_index(f::GiacExpr, varnames)
    base = iscall(f) && symb_funcname(f) == "^" ? string(arguments(f)[1]) : string(f)
    return something(findfirst(==(base), varnames), length(varnames) + 1)
end

# the power of the variable named `v` among the factors of a monomial
function _power(factors, v::String)
    for f in factors
        string(f) == v && return 1
        iscall(f) && symb_funcname(f) == "^" && string(arguments(f)[1]) == v && return _degree(f)
    end
    return 0
end
