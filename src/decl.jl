# @giac_var: declare Giac variables, with assumptions, arrays and renaming.
#
# Modified from https://github.com/jverzani/SymPyCore.jl/blob/main/src/decl.jl
# (originally by @matthieubulte in https://github.com/JuliaPy/SymPy.jl/pull/419).
#
# The macro only parses its arguments. Everything that depends on values —
# array ranges, predicate bounds, `v -> ...` assumptions — is left as code
# that runs in the caller's module, so the macro works inside functions and
# packages (no `eval` at expansion time) and sees local variables.

"""
    @giac_var x y::(integer, positive) z[1:4] u[1:2]::integer v=>"𝑣" w(t)

Declare Giac variables and bind them to Julia variables of the same name.
Returns a tuple of what was declared.

Each argument is one of:

* `x`: a symbolic variable.
* `x::assumption` or `x::(assumption, ...)`: a variable with assumptions
  (see below). Symbolics.jl-style metadata, `x [positive, real]` or
  `x [domain = Real]`, is also accepted.
* `z[1:4]`, `z[1:2, -1:1]`: an array of variables `z₁`, `z₂`, … with the
  shape of the ranges. Ranges may use variables, e.g. `z[1:n]`, and can be
  combined with assumptions: `u[1:2]::positive`.
* `w(t)`, `f(x, y)`: a symbolic function of the given variables. Functions
  take no assumptions.
* `v => "𝑣"`: bind the Julia variable `v` to the Giac name `𝑣`. Works with
  functions (`w(t) => "W"`); add assumptions with parentheses:
  `(v => "𝑣")::positive`.

Commas between arguments are allowed: `@giac_var x, y, z`.

## Assumptions

* A domain: `real`, `complex`, `rational`, `integer` (or `Real`, `Complex`,
  `Rational`, `Integer`).
* A named range: `positive`, `negative`, `nonnegative`, `nonpositive`,
  `finite`.
* A comparison with a bound: `<(b)`, `<=(b)`, `>=(b)`, `>(b)`. The bound is
  evaluated where the macro is called, so `>(c)` uses the value of `c`.
* A function: `[domain = v -> v > 0]`, called with the new variable; it must
  return a Giac condition.

An unknown assumption is an error when the macro is expanded.

Declaring a variable resets it: any value bound with `:=` and any earlier
assumption (including one made with `assume`) is removed first. Assumptions
are recorded in Giac's global state, so they apply for the rest of the
session, like `assume`.

# Example
```jldoctest
julia> @giac_var x y::(integer, positive) z[1:2,-1:1] u[1:2]::positive v=>"𝑣" w(t)
(x, y, GiacExpr[z₁_₋₁ z₁_₀ z₁_₁; z₂_₋₁ z₂_₀ z₂_₁], GiacExpr[u₁, u₂], 𝑣, w(t))

julia> Giac.Commands.about(x)
GiacExpr: x

julia> Giac.Commands.about(y)
GiacExpr: assume[integer,[line[0,+infinity]],[0]]

julia> z
2×3 Matrix{GiacExpr}:
 GiacExpr: z₁_₋₁  GiacExpr: z₁_₀  GiacExpr: z₁_₁
 GiacExpr: z₂_₋₁  GiacExpr: z₂_₀  GiacExpr: z₂_₁

julia> Giac.Commands.about(u[2])
GiacExpr: assume[[],[line[0,+infinity]],[0]]

julia> v
GiacExpr: 𝑣

julia> w
GiacExpr: w(t)

julia> n = 3; @giac_var a[1:n]; a
3-element Vector{GiacExpr}:
 GiacExpr: a₁
 GiacExpr: a₂
 GiacExpr: a₃

julia> @giac_var x::(integer, >(2)); Giac.Commands.about(x)
GiacExpr: assume[integer,[line[2,+infinity]],[2]]

julia> @giac_var x::(>(pi)); Giac.Commands.about(x)
GiacExpr: assume[[],[line[pi,+infinity]],[pi]]
```
"""
macro giac_var(xs...)
    if isempty(xs)
        throw(ArgumentError("@giac_var requires at least one argument"))
    end
    # Declarations separated by commas arrive as one tuple expression.
    if length(xs) == 1 && xs[1] isa Expr && xs[1].head == :tuple
        xs = xs[1].args
    end
    return _gensyms(Any[xs...])
end

# Symbolics.jl-style metadata, `x [positive, real]`, arrives as a separate
# `:vect` argument following the variable; fold it into `x::(positive, real)`.
function _merge_metadata(xs)
    res = Any[]
    for x in xs
        if x isa Expr && x.head == :vect
            isempty(res) &&
                throw(ArgumentError("Metadata [ ] must follow a variable"))
            prev = pop!(res)
            meta = length(x.args) == 1 ? x.args[1] : Expr(:tuple, x.args...)
            push!(res, Expr(:(::), prev, meta))
        else
            push!(res, x)
        end
    end
    return res
end

function _gensyms(xs)
    decls = map(parsedecl, _merge_metadata(xs))
    defs = map(gendecl, decls)
    return Expr(:block, defs..., Expr(:tuple, map(d -> esc(sym(d)), decls)...))
end

# ── Parsing ──────────────────────────────────────────────────────────────────
# A declaration parses into a chain of nodes ending in a SymDecl, e.g.
# `(v => "𝑣")::positive` is AssumptionsDecl(NamedDecl(SymDecl(:v))).

abstract type VarDecl end

struct SymDecl <: VarDecl
    sym::Symbol
end

struct NamedDecl <: VarDecl
    name::String
    rest::VarDecl
end

struct FunctionDecl <: VarDecl
    vars::Vector{Symbol}
    rest::VarDecl
end

struct TensorDecl <: VarDecl
    ranges::Vector{Any}     # range expressions, evaluated at run time
    rest::VarDecl
end

struct AssumptionsDecl <: VarDecl
    assumptions::Vector{Any}  # expressions building `_Assumption`s
    rest::VarDecl
end

function parsedecl(expr)
    # @giac_var x
    if expr isa Symbol
        return SymDecl(expr)

    # @giac_var x::assumption, x::(assumption, ...)
    elseif expr isa Expr && expr.head == :(::)
        length(expr.args) == 2 || parseerror()
        symexpr, spec = expr.args
        specs = spec isa Expr && spec.head == :tuple ? spec.args : Any[spec]
        return AssumptionsDecl(map(_parse_assumption, specs), parsedecl(symexpr))

    # @giac_var x => "name"
    elseif expr isa Expr && expr.head == :call && expr.args[1] == :(=>)
        length(expr.args) == 3 || parseerror()
        expr.args[3] isa String || parseerror()
        return NamedDecl(expr.args[3], parsedecl(expr.args[2]))

    # @giac_var f(x, y)
    elseif expr isa Expr && expr.head == :call
        funcname, funcargs... = expr.args
        if !(funcname isa Symbol)
            throw(ArgumentError("Function name must be a symbol, got $(typeof(funcname)): $funcname"))
        end
        if isempty(funcargs)
            throw(ArgumentError("Function syntax requires at least one argument: @giac_var $(funcname)() is invalid. Use @giac_var $funcname for a simple variable."))
        end
        for (i, farg) in enumerate(funcargs)
            if !(farg isa Symbol)
                throw(ArgumentError("Function arguments must be symbols, got $(typeof(farg)): $farg in position $i"))
            end
        end
        return FunctionDecl(Symbol[funcargs...], SymDecl(funcname))

    # @giac_var x[1:5, 3:9]
    elseif expr isa Expr && expr.head == :ref
        length(expr.args) > 1 || parseerror()
        return TensorDecl(Any[expr.args[2:end]...], parsedecl(expr.args[1]))
    end
    parseerror()
end

const _DOMAINS = Dict(:real => "real", :Real => "real",
                      :complex => "complex", :Complex => "complex",
                      :rational => "rational", :Rational => "rational",
                      :integer => "integer", :Integer => "integer")
const _RANGES = Dict(:positive => :positive, :Positive => :positive,
                     :negative => :negative, :nonnegative => :nonnegative,
                     :nonpositive => :nonpositive, :finite => :finite)
const _COMPARISONS = (:<, :<=, :>=, :>)

# Turn one assumption, as written, into code that builds an `_Assumption`.
# Values (bounds, functions) are escaped so they are evaluated in the
# caller's scope when the declaration runs.
function _parse_assumption(a)
    if a isa Expr && a.head == :(=) && a.args[1] == :domain
        return _parse_assumption(a.args[2])
    elseif a isa Symbol && haskey(_DOMAINS, a)
        return :($(GlobalRef(@__MODULE__, :_DomainAssumption))($(_DOMAINS[a])))
    elseif a isa Symbol && haskey(_RANGES, a)
        return :($(GlobalRef(@__MODULE__, :_RangeAssumption))($(QuoteNode(_RANGES[a]))))
    elseif a isa Expr && a.head == :call && length(a.args) == 2 &&
           a.args[1] in _COMPARISONS
        op, bound = a.args
        return :($(GlobalRef(@__MODULE__, :_CmpAssumption))($(string(op)), $(esc(bound))))
    elseif a isa Expr && a.head == :->
        return :($(GlobalRef(@__MODULE__, :_FnAssumption))($(esc(a))))
    end
    throw(ArgumentError(
        "Unknown @giac_var assumption `$a`. Use a domain (real, complex, " *
        "rational, integer), a range (positive, negative, nonnegative, " *
        "nonpositive, finite), a comparison such as >(0), or a function " *
        "such as [domain = v -> v > 0]."))
end

sym(x::SymDecl) = x.sym
sym(x::VarDecl) = sym(x.rest)

# ── Code generation ──────────────────────────────────────────────────────────

# Flatten a declaration chain into its parts.
function _declparts(x::VarDecl)
    name = nothing
    ranges = nothing
    funcvars = nothing
    assumptions = Any[]
    node = x
    while !(node isa SymDecl)
        if node isa NamedDecl
            name === nothing && (name = node.name)
        elseif node isa TensorDecl
            ranges === nothing || parseerror()
            ranges = node.ranges
        elseif node isa FunctionDecl
            funcvars = node.vars
        elseif node isa AssumptionsDecl
            append!(assumptions, node.assumptions)
        end
        node = node.rest
    end
    name = something(name, String(node.sym))
    return (; name, ranges, funcvars, assumptions)
end

function gendecl(x::VarDecl)
    p = _declparts(x)
    G(f) = GlobalRef(@__MODULE__, f)
    if p.funcvars !== nothing
        p.ranges === nothing || throw(ArgumentError(
            "@giac_var: arrays of functions are not supported"))
        isempty(p.assumptions) || throw(ArgumentError(
            "@giac_var: functions take no assumptions; declare assumptions " *
            "on their variables instead"))
        rhs = :($(G(:_declare_function))($(p.name), $(String.(p.funcvars))))
    else
        assumptions = :($(G(:_Assumption))[$(p.assumptions...)])
        rhs = if p.ranges === nothing
            :($(G(:_declare_symbol))($(p.name), $assumptions))
        else
            :($(G(:_declare_array))($(p.name), ($(map(esc, p.ranges)...),),
                                    $assumptions))
        end
    end
    return :($(esc(sym(x))) = $rhs)
end

# ── Run time ─────────────────────────────────────────────────────────────────

abstract type _Assumption end

struct _DomainAssumption <: _Assumption
    domain::String
end

struct _RangeAssumption <: _Assumption
    kind::Symbol
end

struct _CmpAssumption <: _Assumption
    op::String
    bound::Any
end

struct _FnAssumption <: _Assumption
    f::Any
end

# A Julia bound written as Giac source.
_giac_source(b::GiacExpr) = string(b)
_giac_source(b::Integer) = string(b)
_giac_source(b::Rational) = "($(numerator(b)))/($(denominator(b)))"
_giac_source(b::AbstractFloat) = string(b)
function _giac_source(b::AbstractIrrational)
    b === Base.MathConstants.pi && return "pi"
    b === Base.MathConstants.e && return "exp(1)"
    return string(Float64(b))
end
_giac_source(b) = throw(ArgumentError(
    "@giac_var: cannot use $(repr(b)) of type $(typeof(b)) as a bound"))

_additionally!(x, a::_DomainAssumption) = nothing   # applied with `assume`
function _additionally!(x, a::_RangeAssumption)
    k = a.kind
    k === :positive && return Commands.additionally(x > 0)
    k === :negative && return Commands.additionally(x < 0)
    k === :nonnegative && return Commands.additionally(x >= 0)
    k === :nonpositive && return Commands.additionally(x <= 0)
    if k === :finite
        Commands.additionally("$x > -infinity")
        return Commands.additionally("$x < +infinity")
    end
end
_additionally!(x, a::_CmpAssumption) =
    Commands.additionally("$x $(a.op) $(_giac_source(a.bound))")
_additionally!(x, a::_FnAssumption) = Commands.additionally(a.f(x))

# Declare one Giac variable: clear any value or assumption it had, then
# apply the domain (with `assume`) and the other assumptions (with
# `additionally`, so they combine).
function _declare_symbol(name::String, assumptions::Vector{_Assumption})
    giac_eval("purge($name)")
    x = giac_eval(name)
    for a in assumptions
        a isa _DomainAssumption && Commands.assume(x, a.domain)
    end
    for a in assumptions
        _additionally!(x, a)
    end
    return x
end

const _SUBSCRIPTS = Dict{Char,Char}(
    '-' => '₋', '0' => '₀', '1' => '₁', '2' => '₂', '3' => '₃', '4' => '₄',
    '5' => '₅', '6' => '₆', '7' => '₇', '8' => '₈', '9' => '₉')

map_subscripts(i::Integer) = join(_SUBSCRIPTS[c] for c in string(i))

# Declare an array of variables `name₁`, `name₂`, … (`name₁_₋₁` for several
# dimensions) with the shape of `ranges`.
function _declare_array(name::String, ranges::Tuple,
                        assumptions::Vector{_Assumption})
    for r in ranges
        r isa AbstractRange{<:Integer} || throw(ArgumentError(
            "@giac_var: array dimensions must be integer ranges, got $(repr(r))"))
    end
    return GiacExpr[
        _declare_symbol(name * join(map(map_subscripts, ind), "_"), assumptions)
        for ind in Iterators.product(ranges...)]
end

_declare_function(name::String, vars::Vector{String}) =
    giac_eval("$name($(join(vars, ",")))")

function parseerror()
    throw(ArgumentError("Incorrect @giac_var syntax. Try `@giac_var x::(real,positive) y(t) z::complex n::integer` for instance."))
end
