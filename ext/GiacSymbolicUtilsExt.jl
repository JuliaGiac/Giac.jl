# Exact conversion between Giac and SymbolicUtils, with SymbolicUtils alone (no Symbolics).
#
# Written for MathInterchange's adapter (their feedback, point 5): numbers stay exact (Int or
# BigInt, Rational{BigInt}), radicals and constants stay unevaluated terms (`sqrt(2)`, never
# 1.414…; `2π` is not folded into a float), and in exact mode a float or an unknown function is
# an ArgumentError rather than a guess. Variables are mapped by the caller, so a fresh Giac name
# can come back as the caller's own symbol.
module GiacSymbolicUtilsExt

using Giac
using Giac: GiacExpr
using SymbolicUtils
const SU = SymbolicUtils

# Functions kept in exact mode, besides the arithmetic and the comparisons: elementary
# functions SymbolicUtils builds as terms on symbolic arguments.
const _ELEMENTARY = Set{Any}([sqrt, abs, sign, exp, log, sin, cos, tan, asin, acos, atan,
                              sinh, cosh, tanh, asinh, acosh, atanh, floor, ceil])
const _ARITHMETIC = Set{Any}([(+), (-), (*), (/), (^), inv])
const _RELATIONS = Set{Any}([(<), (<=), (>), (>=), (==), (!=), (&), (|), (!)])

_inexact(what) = throw(ArgumentError(
    "no exact SymbolicUtils form for $what; pass `exact = false` to accept it"))

_isnumber(a) = a isa Number

function _from_leaf(g::GiacExpr, symbols, exact::Bool, strict::Bool)
    t = Giac.giac_type(g)
    if t == Giac.GenTypes.INT || t == Giac.GenTypes.ZINT
        n = Giac.to_julia(g)
        return n isa Integer ? n : _inexact(string(g))
    elseif t == Giac.GenTypes.FRAC
        q = Giac.to_julia(g)
        return Rational{BigInt}(q)
    elseif t == Giac.GenTypes.DOUBLE || t == Giac.GenTypes.REAL
        exact && _inexact("the float $(string(g))")
        return Giac.to_julia(g)
    elseif t == Giac.GenTypes.CPLX
        re = _from(Giac.real_part(g), symbols, exact, strict)
        im_ = _from(Giac.imag_part(g), symbols, exact, strict)
        return re + im_ * im
    elseif t == Giac.GenTypes.IDNT
        name = string(g)
        haskey(symbols, name) && return symbols[name]
        name == "pi" && return SU.term(identity, π)     # a term, so that 2π is not folded
        name == "i" && return im
        strict && throw(ArgumentError("the Giac name `$name` is not in `symbols` (strict_symbols = true)"))
        sym = SU.Sym{SU.SymReal}(Symbol(name); type = Real)
        symbols[name] = sym
        return sym
    end
    exact && _inexact("the Giac value $(string(g)) of type $t")
    return Giac.to_julia(g)
end

# A rational power: `sqrt` for 1/2 (as users write it), never evaluated on a number.
function _power(base, ex)
    if ex isa Integer
        return _isnumber(base) ? Rational{BigInt}(base)^ex |> _simplest : base^ex
    elseif ex isa Rational && isone(2 * ex) && !(_isnumber(base) && isone(base))
        return _isnumber(base) ? SU.term(sqrt, base) : sqrt(base)
    end
    return _isnumber(base) && _isnumber(ex) ? SU.term(^, base, ex) : base^ex
end

# an exact number as Int, BigInt or Rational{BigInt}
_simplest(q::Rational{BigInt}) = isone(denominator(q)) ? _simplest(numerator(q)) : q
_simplest(n::BigInt) = typemin(Int) <= n <= typemax(Int) ? Int(n) : n
_simplest(x) = x

function _from(g::GiacExpr, symbols, exact::Bool, strict::Bool = false)
    Giac.iscall(g) || return _from_leaf(g, symbols, exact, strict)
    op = Giac.operation(g)
    args = [_from(a, symbols, exact, strict) for a in Giac.arguments(g)]
    if !(op isa Function)
        exact && _inexact("the Giac function $(Giac.symb_funcname(g))")
        return SU.term(op, args...)
    end
    numeric = all(_isnumber, args)
    if op === (^) && length(args) == 2
        return _power(args[1], args[2])
    elseif op === inv && length(args) == 1
        return numeric ? _simplest(1 // Rational{BigInt}(only(args))) : inv(only(args))
    elseif op === (/) && numeric && length(args) == 2
        return _simplest(Rational{BigInt}(args[1]) // Rational{BigInt}(args[2]))   # 1/3, not 0.333…
    elseif op === exp && numeric
        return SU.term(exp, args...)                    # exp(1) stays e, not 2.718…
    elseif op in _ARITHMETIC || op in _RELATIONS
        return numeric ? _simplest(op(map(a -> a isa Integer ? big(a) : a, args)...)) : op(args...)
    elseif op in _ELEMENTARY || !exact
        return numeric ? SU.term(op, args...) : op(args...)
    end
    _inexact("the function $op")
end

"""
    to_symbolicutils(g::GiacExpr; symbols = Dict{String, Any}(), exact = true, strict_symbols = false)

`g` as a SymbolicUtils expression, with no Symbolics needed. Numbers are exact: `Int` or
`BigInt`, `Rational{BigInt}` for fractions (`inv(2)` is `1//2`). Radicals stay unevaluated
(`sqrt(2)` is a term, never `1.414…`; a rational power `t^(1//2)` is `sqrt(t)`), `π` is kept in a
term so that arithmetic does not fold `2π` into a float, `exp(1)` stays a term and `i` is `im`.

`symbols` maps Giac names to the SymbolicUtils symbols to use; a name not in it becomes a
`Real` symbol of the same name (added to `symbols`), or, with `strict_symbols = true`, is an
`ArgumentError`: an identifier the caller did not expect came back. With `exact = true`, a float or a function
outside the elementary ones is an `ArgumentError`; `exact = false` accepts them.
"""
function Giac.to_symbolicutils(g::GiacExpr; symbols::AbstractDict = Dict{String, Any}(),
                               exact::Bool = true, strict_symbols::Bool = false)
    return GC.@preserve g _from(g, symbols, exact, strict_symbols)
end

# ---------------------------------------------------------------------------------------------
# SymbolicUtils → Giac
# ---------------------------------------------------------------------------------------------

function _to_giac_number(c, exact::Bool)
    c isa Integer && return convert(GiacExpr, c)
    c isa Rational && return convert(GiacExpr, c)
    c isa Complex && return _to_giac_number(real(c), exact) + _to_giac_number(imag(c), exact) * giac_eval("i")
    c isa AbstractIrrational && return convert(GiacExpr, c)
    exact && _inexact_giac(c)
    return convert(GiacExpr, c)
end
_inexact_giac(c) = throw(ArgumentError(
    "no exact Giac form for $(repr(c)); pass `exact = false` to accept it"))

function _to(t, names, exact::Bool)
    t isa Number && return _to_giac_number(t, exact)
    if SU.isconst(t)
        return _to_giac_number(SU.unwrap_const(t), exact)
    elseif SU.issym(t)
        return giac_eval(get(names, t, string(nameof(t))))
    elseif SU.iscall(t)
        op = SU.operation(t)
        args = [_to(a, names, exact) for a in SU.arguments(t)]
        op === identity && length(args) == 1 && return only(args)
        exact && !(op in _ARITHMETIC || op in _RELATIONS || op in _ELEMENTARY) &&
            throw(ArgumentError("no exact Giac form for the function $op"))
        return op(args...)
    end
    throw(ArgumentError("cannot convert $(repr(t)) to Giac"))
end

"""
    to_giac(t::SymbolicUtils.BasicSymbolic; names = Dict(), exact = true)

The SymbolicUtils expression `t` as a `GiacExpr`, built node by node (no string is parsed but the
variables' names). `names` maps SymbolicUtils symbols to the Giac names to use; a symbol not in
it keeps its own name. Comparisons and `&`, `|` become Giac relations and `and`, `or`. With
`exact = true`, a float or a function outside the elementary ones is an `ArgumentError`.
"""
function Giac.to_giac(t::SU.BasicSymbolic; names::AbstractDict = Dict(), exact::Bool = true)
    return _to(t, names, exact)
end

# ---------------------------------------------------------------------------------------------
# SymbolicUtils → Giac source text, unevaluated
# ---------------------------------------------------------------------------------------------

const _GIAC_NAME = Dict{Any, String}(log => "ln")
const _RELATION_TEXT = Dict{Any, String}((<) => "<", (<=) => "<=", (>) => ">", (>=) => ">=",
                                         (==) => "==", (!=) => "!=")
const _CONNECTIVE_TEXT = Dict{Any, String}((&) => " and ", (|) => " or ")

function _number_source(c, exact::Bool)
    if c isa Integer
        return c < 0 ? "($c)" : string(c)
    elseif c isa Rational
        n, d = numerator(c), denominator(c)
        isone(d) && return _number_source(n, exact)
        return "($n/$d)"
    elseif c isa Complex
        return "(" * _number_source(real(c), exact) * "+" * _number_source(imag(c), exact) * "*i)"
    elseif c === π
        return "pi"
    elseif c === ℯ
        return "exp(1)"
    end
    exact && _inexact_giac(c)
    return string(c)
end

function _source(t, names, exact::Bool)
    t isa Number && return _number_source(t, exact)
    SU.isconst(t) && return _number_source(SU.unwrap_const(t), exact)
    SU.issym(t) && return get(names, t, string(nameof(t)))
    SU.iscall(t) || throw(ArgumentError("cannot write $(repr(t)) as Giac source"))
    op = SU.operation(t)
    args = [_source(a, names, exact) for a in SU.arguments(t)]
    n = length(args)
    op === identity && n == 1 && return only(args)
    if op === (+) || op === (*)
        return "(" * join(args, string(op)) * ")"
    elseif op === (-)
        return n == 1 ? "(-" * only(args) * ")" : "(" * join(args, "-") * ")"
    elseif (op === (/) || op === (^)) && n == 2
        return "(" * args[1] * string(op) * args[2] * ")"
    elseif haskey(_RELATION_TEXT, op) && n == 2
        return "(" * args[1] * _RELATION_TEXT[op] * args[2] * ")"
    elseif haskey(_CONNECTIVE_TEXT, op)
        return "(" * join(args, _CONNECTIVE_TEXT[op]) * ")"
    elseif op === (!) && n == 1
        return "(not(" * only(args) * "))"
    elseif op === inv && n == 1
        return "(1/" * only(args) * ")"
    elseif op in _ELEMENTARY || (!exact && op isa Function)
        return get(_GIAC_NAME, op, string(nameof(op))) * "(" * join(args, ",") * ")"
    end
    throw(ArgumentError("no exact Giac source for the function $op"))
end

"""
    Giac.giac_source(t::SymbolicUtils.BasicSymbolic; names = Dict(), exact = true) -> String

The Giac source text of the SymbolicUtils expression `t`, **unevaluated**: what Giac will
receive, to record before it evaluates anything (`to_giac` builds the value instead, and Giac
evaluates each node). `names` maps SymbolicUtils symbols to Giac names. Numbers stay exact
(`(1/3)`), comparisons are Giac relations, `&`, `|` and `!` are `and`, `or` and `not`. With
`exact = true`, a float or a function outside the elementary ones is an `ArgumentError`.

```julia
@syms x::Real
Giac.giac_source((0 < x) & (x <= 10); names = Dict(x => "v"))   # "((0<v) and (v<=10))"
```
"""
function Giac.giac_source(t::SU.BasicSymbolic; names::AbstractDict = Dict(), exact::Bool = true)
    return _source(t, names, exact)
end

end # module
