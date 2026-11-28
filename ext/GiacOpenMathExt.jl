# GIAC expressions as OpenMath objects and back, through the giac-openmath table
# (https://github.com/JuliaGiac/giac-openmath), embedded in giac_openmath_table.jl.
#
# The table maps the nodes of GIAC's trees to OpenMath Content Dictionary symbols
# with patterns: "#1", "#2"… are the node's arguments, "#*" all of them, ["apply",
# f, …] an application whose head is not a symbol, ["bind", binder, [vars], body]
# a binding. This file only walks trees and follows those patterns: what maps to
# what is the table's, so that every program reading it agrees (see the table's
# docs/format.md). What the table does not list, or refuses, is an
# OpenMathConversionError, with the table's reason when it has one.
module GiacOpenMathExt

using Giac
using Giac: GiacExpr
using OpenMath
using OpenMath: OpenMathConversionError
using TOML

include("giac_openmath_table.jl")
const TABLE = TOML.parse(TABLE_TOML)

_direction(e) = get(e, "direction", "both")
_to(e) = _direction(e) != "from_openmath"
_from(e) = _direction(e) != "to_openmath"
_isplaceholder(x) = x isa AbstractString && startswith(x, "#")
_literal(x) = x isa Integer || (x isa AbstractString && !_isplaceholder(x))

_refuse(msg) = throw(OpenMathConversionError(GiacExpr, msg))
_where() = "giac-openmath at $(TABLE_COMMIT[1:7])"

# GIAC identifier => OpenMath symbol, and back
const TO_LEAF = Dict(String(l["giac"]) => String(l["om"]) for l in TABLE["leaf"] if _to(l))
const FROM_LEAF = Dict(String(l["om"]) => String(l["giac"]) for l in TABLE["leaf"] if _from(l))
# refused GIAC nodes or names, and OpenMath symbols => the table's reason
const REFUSED_GIAC = Dict(String(r["giac"]) => String(r["reason"]) for r in TABLE["refused"] if haskey(r, "giac"))
const REFUSED_OM = Dict(String(r["om"]) => String(r["reason"]) for r in TABLE["refused"] if haskey(r, "om"))

# GIAC node => its entries, the ones with literal arguments first
const TO_MAPS = let d = Dict{String, Vector{Any}}()
    for m in TABLE["map"]
        _to(m) && push!(get!(d, String(m["giac"][1]), Any[]), m)
    end
    foreach(v -> sort!(v; by = m -> !any(_literal, m["giac"][2:end])), values(d))
    d
end

# the key of an OpenMath pattern or object: its head symbol, "apply:" and the
# head symbol of an applied application, or "bind:" and the binder
_key(p::AbstractString) = String(p)
function _key(p::AbstractVector)
    p[1] == "apply" && return "apply:" * _key(p[2])
    p[1] == "bind" && return "bind:" * p[2]
    return String(p[1])
end
_key(o::OMSymbol) = o.cd * "." * o.name
_key(o::OMApplication) = o.applicant isa OMSymbol ? _key(o.applicant) :
                         o.applicant isa OMApplication && o.applicant.applicant isa OMSymbol ?
                         "apply:" * _key(o.applicant.applicant) : ""
_key(o::OMBinding) = o.binder isa OMSymbol ? "bind:" * _key(o.binder) : ""
_key(::OMNode) = ""

const FROM_MAPS = let d = Dict{String, Vector{Any}}()
    for m in TABLE["map"]
        _from(m) && push!(get!(d, _key(m["om"]), Any[]), m)
    end
    d
end

# ---------------------------------------------------------------------------------
# GIAC → OpenMath
# ---------------------------------------------------------------------------------

function _symbol(s::AbstractString)
    cd, name = split(s, '.'; limit = 2)
    return OMSymbol(String(cd), String(name))
end

function _leaf(g::GiacExpr)
    T = Giac.GenTypes
    t = Giac.giac_type(g)
    text = string(g)
    if t == T.INT || t == T.ZINT
        text in ("true", "false") && return _symbol(TO_LEAF[text])
        return OMInteger(Giac.to_julia(g))
    elseif t == T.FRAC
        q = Rational{BigInt}(Giac.to_julia(g))
        return OMSymbol("nums1", "rational")(OMInteger(numerator(q)), OMInteger(denominator(q)))
    elseif t == T.CPLX
        haskey(TO_LEAF, text) && return _symbol(TO_LEAF[text])          # i
        return OMSymbol("complex1", "complex_cartesian")(_openmath(Giac.real_part(g)),
                                                         _openmath(Giac.imag_part(g)))
    elseif t == T.DOUBLE
        return OMFloat(Float64(Giac.to_julia(g)))
    elseif t == T.IDNT
        haskey(TO_LEAF, text) && return _symbol(TO_LEAF[text])
        haskey(REFUSED_GIAC, text) && _refuse("GIAC's `$text` has no OpenMath form: $(REFUSED_GIAC[text])")
        return OMVariable(text)
    end
    _refuse("no OpenMath form for the GIAC value `$text` of type $t ($(_where()))")
end

# the arguments of a GIAC node bound to the placeholders of a GIAC pattern, or nothing
function _match_giac(pattern, args)
    ps = pattern[2:end]
    env = Dict{String, Any}()
    if !isempty(ps) && ps[end] == "#*"
        length(args) >= length(ps) || return nothing
        env["#*"] = args[length(ps):end]
        ps = ps[1:end-1]
    else
        length(args) == length(ps) || return nothing
    end
    for (p, a) in zip(ps, args)
        if _isplaceholder(p)
            env[p] = a
        elseif string(a) != string(p)             # a literal integer or name
            return nothing
        end
    end
    return env
end

# the OpenMath object of a pattern, its placeholders taken from env
function _build(p, env)
    p isa Integer && return OMInteger(p)
    if p isa AbstractString
        _isplaceholder(p) && return _openmath(env[p])
        return _symbol(p)
    end
    if p[1] == "apply"
        return OMApplication(_build(p[2], env), _build_args(p[3:end], env))
    elseif p[1] == "bind"
        vars = map(p[3]) do v
            g = env[v]
            Giac.giac_type(g) == Giac.GenTypes.IDNT ||
                _refuse("a bound variable must be a GIAC name, not `$(string(g))`")
            OMBoundVariable(string(g))
        end
        return OMBinding(_symbol(p[2]), vars, _build(p[4], env))
    end
    return OMApplication(_symbol(p[1]), _build_args(p[2:end], env))
end
_build_args(ps, env) = reduce(vcat, (p == "#*" ? map(_openmath, env["#*"]) : [_build(p, env)] for p in ps);
                              init = OMNode[])

function _openmath(g::GiacExpr)
    Giac.iscall(g) || return _leaf(g)
    node = Giac.symb_funcname(g)
    args = Giac.arguments(g)
    for m in get(TO_MAPS, node, Any[])
        env = _match_giac(m["giac"], args)
        env === nothing || return _build(m["om"], env)
    end
    haskey(REFUSED_GIAC, node) && _refuse("GIAC's `$node` is not mapped to OpenMath: $(REFUSED_GIAC[node])")
    _refuse("no OpenMath symbol for the GIAC node `$node` with $(length(args)) argument(s) in $(_where())")
end

OpenMath.to_openmath(g::GiacExpr) = GC.@preserve g _openmath(g)

# ---------------------------------------------------------------------------------
# OpenMath → GIAC input
# ---------------------------------------------------------------------------------

const _STANDARD_CDBASE = (nothing, "http://www.openmath.org/cd")

_is(o::OMSymbol, s::AbstractString) = o.cdbase in _STANDARD_CDBASE && _key(o) == s
_is(::Any, ::AbstractString) = false

# bind env[p] = o, or check it is what it already is
function _bind!(env, p, o)
    haskey(env, p) && return env[p] == o
    env[p] = o
    return true
end

function _match_om(p, o, env)
    p isa Integer && return o isa OMInteger && o.value == p
    if p isa AbstractString
        _isplaceholder(p) && return _bind!(env, p, o)
        return _is(o, p)
    end
    if p[1] == "apply"
        return o isa OMApplication && _match_om(p[2], o.applicant, env) &&
               _match_om_args(p[3:end], o.arguments, env)
    elseif p[1] == "bind"
        o isa OMBinding && _is(o.binder, p[2]) && length(o.variables) == length(p[3]) || return false
        for (v, bv) in zip(p[3], o.variables)
            isempty(bv.attributes) && _bind!(env, v, OMVariable(bv.name)) || return false
        end
        return _match_om(p[4], o.body, env)
    end
    return o isa OMApplication && _is(o.applicant, p[1]) && _match_om_args(p[2:end], o.arguments, env)
end

function _match_om_args(ps, args, env)
    if !isempty(ps) && ps[end] == "#*"
        n = length(ps) - 1
        length(args) > n || return false
        all(_match_om(p, a, env) for (p, a) in zip(ps[1:n], args)) || return false
        env["#*"] = args[n+1:end]
        return true
    end
    length(ps) == length(args) || return false
    return all(_match_om(p, a, env) for (p, a) in zip(ps, args))
end

# GIAC input for an entry's GIAC pattern, its placeholders written from env
function _write(m, env)
    pattern = m["giac"]
    head = strip(pattern[1])
    args = String[]
    for a in pattern[2:end]
        if a == "#*"
            append!(args, map(_source, env["#*"]))
        elseif _isplaceholder(a)
            push!(args, _source(env[a]))
        else
            push!(args, string(a))
        end
    end
    input = get(m, "input", "call")
    input == "call" && return string(head, "(", join(args, ", "), ")")
    (input == "prefix" || length(args) == 1) && return string(head, "(", only(args), ")")
    return join(("(" * a * ")" for a in args), " " * head * " ")
end

_number(n) = n < 0 ? "($n)" : string(n)

_source(o::OMInteger) = _number(o.value)
_source(o::OMFloat) = isfinite(o.value) ? _number(o.value) : _refuse("no GIAC form for the float $(o.value)")

function _source(o::OMVariable)
    name = o.name
    occursin(Giac._IDENTIFIER_PATTERN, name) ||
        _refuse("the OpenMath variable `$name` is not a GIAC identifier")
    (name in Giac._RESERVED_NAMES || Giac.is_valid_command(name)) &&
        _refuse("the OpenMath variable `$name` is a GIAC constant or command, so GIAC would read it as one")
    return name
end

function _source(o::OMSymbol)
    s = _key(o)
    o.cdbase in _STANDARD_CDBASE || _refuse("no GIAC form for the symbol $s of the CD base $(o.cdbase)")
    haskey(FROM_LEAF, s) && return FROM_LEAF[s]
    haskey(REFUSED_OM, s) && _refuse("$s is not mapped to GIAC: $(REFUSED_OM[s])")
    _refuse("no GIAC form for the OpenMath symbol $s in $(_where())")
end

function _source(o::Union{OMApplication, OMBinding})
    key = _key(o)
    # the number constructors the table leaves to the leaf conventions
    if o isa OMApplication && _is(o.applicant, "nums1.rational") && length(o.arguments) == 2 &&
       all(a -> a isa OMInteger, o.arguments)
        return "(" * _source(o.arguments[1]) * "/" * _source(o.arguments[2]) * ")"
    elseif o isa OMApplication && _is(o.applicant, "complex1.complex_cartesian") && length(o.arguments) == 2
        return "((" * _source(o.arguments[1]) * ")+(" * _source(o.arguments[2]) * ")*i)"
    end
    for m in get(FROM_MAPS, key, Any[])
        env = Dict{String, Any}()
        _match_om(m["om"], o, env) && return _write(m, env)
    end
    head = replace(key, r"^(apply|bind):" => "")
    haskey(REFUSED_OM, head) && _refuse("$head is not mapped to GIAC: $(REFUSED_OM[head])")
    isempty(head) && _refuse("no GIAC form for this OpenMath $(nameof(typeof(o))) in $(_where())")
    _refuse("no GIAC form for $head with these arguments in $(_where())")
end

_source(o::OMNode) = _refuse("no GIAC form for an OpenMath $(nameof(typeof(o)))")

Giac.giac_source(o::OMNode) = _source(o)

"""
    Giac.from_openmath(o::OpenMath.OMNode) -> GiacExpr

The GIAC expression of the OpenMath object `o`, evaluated by GIAC (so an
integral is computed); `Giac.giac_source(o)` is the GIAC input, not evaluated.
"""
Giac.from_openmath(o::OMNode) = giac_eval(_source(o))

end # module
