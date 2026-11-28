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

# format 2: each CD's status and base, and the CDs whose symbols are requests
const STANDARD_CDBASE = "http://www.openmath.org/cd"
_cd_entry(cd) = get(TABLE["cd"], cd, nothing)
_status(cd) = (e = _cd_entry(cd); e === nothing ? nothing : e["status"])
_base_of(cd) = (e = _cd_entry(cd); e === nothing ? STANDARD_CDBASE : get(e, "cdbase", STANDARD_CDBASE))
_needs_enabling(cd) = _status(cd) in ("experimental", "private")
const PROCEDURE_CDS = Set{String}(TABLE["envelope"]["procedure_cds"])
const CALL = String(TABLE["envelope"]["call"])

# the CDs a caller enables, checked against the table
function _enabled(enable)
    en = Set{String}(String.(collect(enable)))
    for cd in en
        haskey(TABLE["cd"], cd) || throw(ArgumentError("enable: `$cd` is not a Content Dictionary of the table"))
    end
    return en
end

function _not_enabled(cd, s)
    what = _status(cd) == "private" ? "a private" : "an experimental"
    _refuse("$cd is $what Content Dictionary: $s is used only when the caller enables it (enable = [\"$cd\"])")
end

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
    base = _base_of(cd)
    return OMSymbol(String(cd), String(name); cdbase = base == STANDARD_CDBASE ? nothing : base)
end

# the symbols of a result: those of CDs that need enabling only when enabled
_check_out(o::OMSymbol, en) = (_needs_enabling(o.cd) && !(o.cd in en) && _not_enabled(o.cd, _key(o)); nothing)
_check_out(o::OMApplication, en) = (_check_out(o.applicant, en); foreach(a -> _check_out(a, en), o.arguments))
_check_out(o::OMBinding, en) = (_check_out(o.binder, en); _check_out(o.body, en))
_check_out(::Any, en) = nothing

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

"""
    OpenMath.to_openmath(g::GiacExpr; enable = ()) -> OMNode

The OpenMath object of `g`, in the table's official Content Dictionaries. The
others (`giac_math1`…) are used only when listed in `enable`; JuliaGiac's own
CDs carry their base, `https://juliagiac.github.io/giac-openmath/cd`.
"""
function OpenMath.to_openmath(g::GiacExpr; enable = ())
    en = _enabled(enable)
    o = GC.@preserve g _openmath(g)
    _check_out(o, en)
    return o
end

# ---------------------------------------------------------------------------------
# OpenMath → GIAC input
# ---------------------------------------------------------------------------------

# a symbol at its CD's base (_prepare gives every symbol its base)
_at_base(o::OMSymbol) = something(o.cdbase, STANDARD_CDBASE) == _base_of(o.cd)
_is(o::OMSymbol, s::AbstractString) = _at_base(o) && _key(o) == s
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
    _at_base(o) || _refuse("no GIAC form for the symbol $s of the CD base $(o.cdbase)")
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
    # a free variable named as a constant, where a bound one was renamed
    # (diff(i -> i^2) applied to i): refuse that variable, not the shape
    v = _first_reserved(o)
    v === nothing || _source(v)
    head = replace(key, r"^(apply|bind):" => "")
    haskey(REFUSED_OM, head) && _refuse("$head is not mapped to GIAC: $(REFUSED_OM[head])")
    isempty(head) && _refuse("no GIAC form for this OpenMath $(nameof(typeof(o))) in $(_where())")
    _refuse("no GIAC form for $head with these arguments in $(_where())")
end

_source(o::OMNode) = _refuse("no GIAC form for an OpenMath $(nameof(typeof(o)))")

# ---------------------------------------------------------------------------------
# Reading rules of format 2, before any GIAC input is written
# ---------------------------------------------------------------------------------

# the first symbol, in document order, of a CD not enabled, at another base, or a
# request out of place; and floats, when exact
function _check(o::OMSymbol, c, head = false)
    s = _key(o)
    _needs_enabling(o.cd) && !(o.cd in c.enable) && _not_enabled(o.cd, s)
    _at_base(o) || _refuse("no GIAC form for the symbol $s of the CD base $(o.cdbase): $(o.cd) is at $(_base_of(o.cd))")
    o.cd in PROCEDURE_CDS && !head &&
        _refuse("$s is a request to GIAC: valid only as the head of the argument of $CALL")
    return nothing
end
function _check(o::OMApplication, c, head = false)
    _check(o.applicant, c)
    call = o.applicant isa OMSymbol && _key(o.applicant) == CALL
    for (i, a) in enumerate(o.arguments)
        if call && i == 1 && a isa OMApplication
            _check(a.applicant, c, true)
            foreach(x -> _check(x, c), a.arguments)
        else
            _check(a, c)
        end
    end
    call && _refuse("GiacOpenMathExt does not evaluate requests ($CALL) yet")
    return nothing
end
function _check(o::OMBinding, c, head = false)
    _check(o.binder, c)
    for v in o.variables, p in v.attributes
        _check(p.key, c); _check(p.value, c)
    end
    _check(o.body, c)
end
function _check(o::OMAttribution, c, head = false)
    for p in o.attributes
        _check(p.key, c); _check(p.value, c)
    end
    _check(o.object, c)
end
_check(o::OMFloat, c, head = false) = c.exact ? _refuse("a float, refused in exact mode") : nothing
_check(::Any, c, head = false) = nothing

# every variable name of an object
_names!(s, o::OMVariable) = push!(s, o.name)
_names!(s, o::OMApplication) = (_names!(s, o.applicant); foreach(a -> _names!(s, a), o.arguments); s)
_names!(s, o::OMBinding) = (foreach(v -> push!(s, v.name), o.variables); _names!(s, o.binder); _names!(s, o.body))
_names!(s, ::Any) = s

# bound variables named as GIAC constants renamed to fresh names, the name
# followed by _1, _2…, the first no variable of the object uses (alpha-conversion)
_rename(o::OMVariable, sub, fresh) = haskey(sub, o.name) ? OMVariable(sub[o.name]) : o
_rename(o::OMApplication, sub, fresh) =
    OMApplication(_rename(o.applicant, sub, fresh), [_rename(a, sub, fresh) for a in o.arguments])
function _rename(o::OMBinding, sub, fresh)
    inner = copy(sub)
    vars = map(o.variables) do v
        if v.name in Giac._RESERVED_NAMES
            n = fresh(v.name)
            inner[v.name] = n
            OMBoundVariable(n, v.attributes)
        else
            delete!(inner, v.name)            # a bound name shadows an outer renaming
            v
        end
    end
    return OMBinding(_rename(o.binder, sub, fresh), vars, _rename(o.body, inner, fresh))
end
_rename(o, sub, fresh) = o

function _rename(o)
    used = _names!(Set{String}(), o)
    fresh = function (n)
        k = 1
        while "$(n)_$k" in used
            k += 1
        end
        push!(used, "$(n)_$k")
        return "$(n)_$k"
    end
    return _rename(o, Dict{String, String}(), fresh)
end

# the first variable named as a GIAC constant: after _rename, a free one
_first_reserved(o::OMVariable) = o.name in Giac._RESERVED_NAMES ? o : nothing
function _first_reserved(o::OMApplication)
    for x in (o.applicant, o.arguments...)
        r = _first_reserved(x)
        r === nothing || return r
    end
    return nothing
end
_first_reserved(o::OMBinding) = something(_first_reserved(o.binder), _first_reserved(o.body), Some(nothing))
_first_reserved(::Any) = nothing

# the object _source reads: bases explicit, the rules checked, bound names renamed
function _prepare(o::OMObject, enable, exact)
    base = o.cdbase === nothing ? STANDARD_CDBASE : o.cdbase
    return _prepare(resolve_cdbase(o.object; base), enable, exact; resolved = true)
end
function _prepare(o::OMNode, enable, exact; resolved = false)
    r = resolved ? o : resolve_cdbase(o)
    _check(r, (; enable = _enabled(enable), exact = Bool(exact)))
    return _rename(r)
end

"""
    Giac.giac_source(o::OpenMath.OMNode; enable = (), exact = false) -> String

The GIAC input of the OpenMath object `o`, not evaluated. Only the table's
official Content Dictionaries are read, unless `enable` lists others
(`giac_math1`, `scscp1`, `prog1`, `giac_procedures1`); each symbol must be at
its CD's base, its own `cdbase` or the nearest enclosing object's. Request
symbols are refused outside `scscp1.procedure_call`, and requests are not
evaluated yet. `exact = true` refuses floats.
"""
Giac.giac_source(o::Union{OMNode, OMObject}; enable = (), exact = false) = _source(_prepare(o, enable, exact))

"""
    Giac.from_openmath(o::OpenMath.OMNode; enable = (), exact = false) -> GiacExpr

The GIAC expression of the OpenMath object `o`, evaluated by GIAC (so an
integral is computed); `Giac.giac_source(o)` is the GIAC input, not evaluated,
and says which objects are read.
"""
Giac.from_openmath(o::Union{OMNode, OMObject}; enable = (), exact = false) =
    giac_eval(Giac.giac_source(o; enable, exact))

end # module
