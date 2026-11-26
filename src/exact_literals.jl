# Numbers Julia computes in floating point before Giac sees them, written exactly: `0.1` is the
# binary double nearest 1/10, in `2π * x` the product 2π is a Float64, and `sqrt(2)` is 1.414….
# For macros whose code is symbolic.

"""
    _exact_literals(ex)

The code `ex` with the numbers Julia would compute in floating point made exact:

- a float literal (`0.1`, `2.5e-3`, `1.5f0`) as the fraction its shortest decimal form reads
  (`1/10`, `1/400`, `3/2`), and so is `big(0.1)` or `big"0.1"`;
- `π` and `pi` as Giac's π, `ℯ` as e;
- `sqrt(2)` and `cbrt(2)` of an integer literal as roots, and `2^(1//3)` or `2^-1`, an integer
  literal to a fractional or negative power, as a power of the Giac integer;
- `1/2` of two integer literals as the Giac fraction.

Each becomes a `GiacExpr`. Integer literals and integer arithmetic are left as written, as are
names (a float held in a variable is not a literal), quoted code and the code of other macros.
Meant for the symbolic code a macro runs, not for numeric code, where π should stay a float.
"""
_exact_literals(ex) = ex
_exact_literals(x::Union{Float64, Float32}) = _exact_call(_rational_code(_shortest_rational(x)))
function _exact_literals(s::Symbol)
    s in (:π, :pi) && return _exact_call(GlobalRef(Base.MathConstants, :π))
    s === :ℯ && return _exact_call(GlobalRef(Base.MathConstants, :ℯ))
    return s
end
function _exact_literals(ex::Expr)
    ex.head in (:quote, :inert) && return ex
    if ex.head === :macrocall
        r = _big_decimal(ex)
        return r === nothing ? ex : _exact_call(_rational_code(r))
    end
    if ex.head === :call && length(ex.args) == 2
        f, a = ex.args
        if f === :big                       # big(0.1): the exact number, not a BigFloat of the double
            e = _exact_literals(a)
            _is_exact_call(e) && return e
        end
        f in (:sqrt, :cbrt) && _is_int_literal(a) && return Expr(:call, GlobalRef(Base, f), _exact_call(a))
    end
    if ex.head === :call && length(ex.args) == 3
        f, a, b = ex.args
        f === :/ && _is_int_literal(a) && _is_int_literal(b) &&
            return _exact_call(Expr(:call, GlobalRef(Base, ://), a, b))
        f === :^ && _is_int_literal(a) && !(_is_int_literal(b) && b >= 0) &&
            return Expr(:call, GlobalRef(Base, :^), _exact_call(a), _exact_literals(b))
    end
    return Expr(ex.head, map(_exact_literals, ex.args)...)
end

_is_int_literal(a) = a isa Integer && !(a isa Bool)

_exact_call(x) = Expr(:call, GlobalRef(Base, :convert), GlobalRef(@__MODULE__, :GiacExpr), x)
_is_exact_call(e) = e isa Expr && e.head === :call && length(e.args) == 3 &&
    e.args[1] == GlobalRef(Base, :convert) && e.args[2] == GlobalRef(@__MODULE__, :GiacExpr)

"""
    _shortest_rational(x::Union{Float64, Float32}) -> Rational

The fraction that the shortest decimal form of `x` reads, the digits Julia prints for it:
`0.1` is `1//10`, not the binary value 3602879701896397//36028797018963968, and `2.5e-3`
is `1//400`. A `Rational{Int}` when it fits, a `Rational{BigInt}` otherwise (`1e300`).
"""
function _shortest_rational(x::Union{Float64, Float32})
    isfinite(x) || throw(ArgumentError("$x has no exact value"))
    return _decimal_rational(string(x))
end

const _DECIMAL = r"^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$"

# the fraction a decimal string reads, or nothing for what is not a decimal number
function _decimal_rational(s::AbstractString)
    m = match(_DECIMAL, s)
    m === nothing && return nothing
    sign, int, frac, exp10 = m.captures
    frac = something(frac, "")
    digits = int * frac
    isempty(digits) && return nothing
    e = (exp10 === nothing ? 0 : parse(Int, exp10)) - length(frac)
    abs(e) > 100_000 && return nothing                         # not worth 10^e digits
    n = parse(BigInt, digits)
    r = e >= 0 ? (n * big(10)^e) // 1 : n // big(10)^(-e)
    r = sign == "-" ? -r : r
    fits = typemin(Int) <= numerator(r) <= typemax(Int) && denominator(r) <= typemax(Int)
    return fits ? Rational{Int}(r) : r
end

# `big"0.1"` read as the fraction it writes; `big"123"`, already an exact integer, is not
function _big_decimal(ex::Expr)
    length(ex.args) == 3 && ex.args[3] isa String || return nothing
    name = ex.args[1] isa GlobalRef ? ex.args[1].name : ex.args[1]
    name === Symbol("@big_str") || return nothing
    s = ex.args[3]
    occursin(r"[.eE]", s) || return nothing
    return _decimal_rational(s)
end

# code building the rational at run time: a BigInt is not left as a constant in compiled code
_rational_code(r::Rational) = Expr(:call, GlobalRef(Base, ://), _integer_code(numerator(r)), _integer_code(denominator(r)))
_integer_code(n::Int) = n
_integer_code(n::BigInt) = typemin(Int) <= n <= typemax(Int) ? Int(n) :
    Expr(:call, GlobalRef(Base, :parse), GlobalRef(Base, :BigInt), string(n))

"""
    @exact expr

`expr` with its numbers kept exact. A float literal is read as the decimal it is written as,
so `@exact 0.1 + 0.2` is the Giac fraction `3/10` (Julia's `0.1 + 0.2` is
`0.30000000000000004`); `@exact 2π * x` is 2πx with Giac's π rather than `6.283…*x`, and
`@exact sqrt(2) / 2` is √2/2. A function cannot do this, as `0.1` and `2π` are floats before any
function sees them.

Rewritten into exact `GiacExpr` values: float literals (each read from its shortest decimal
form, `2.5e-3` is `1/400`; `big(0.1)` and `big"0.1"` too), `π`, `pi` and `ℯ`, `sqrt` and `cbrt`
of an integer literal, an integer literal to a fractional or negative power (`2^(1/3)`, `2^-1`),
and the quotient `1/2` of two integer literals. Left as written: integer literals and integer
arithmetic (`2 * 3` is the Julia `6`), names, whatever their value (`y = 0.1; @exact y * x` still
has the float), qualified constants (`Base.pi`), quoted code, and code inside another macro call
(`@exact` nested in it expands on its own). A block works too. A name assigned an integer or a
rational by the macro's own assignments (those of its block, not of a loop or function inside it)
is bound to the Giac number, so that what is computed from it later is exact as well.

All literals of `expr` are rewritten, so keep numeric code (ranges, tolerances, plotting) out of
it.

```julia
@exact 0.1 + 0.2                             # 3/10
@giac_var x a::positive
@exact 0.5x^2 - 1.25                         # 1/2*x^2-5/4
φ = @exact sqrt(2 / a) * sin(2π * x / a)     # √(2/a) sin(2πx/a)
@exact three = 3                             # a Giac 3: sqrt(three) is √3
```
"""
macro exact(ex)
    return esc(_exact_bindings(_exact_literals(ex)))
end

_exact_bindings(ex) = ex
function _exact_bindings(ex::Expr)
    ex.head === :block && return Expr(:block, map(_exact_bindings, ex.args)...)
    ex.head === :(=) && ex.args[1] isa Symbol &&
        return Expr(:(=), ex.args[1], Expr(:call, GlobalRef(@__MODULE__, :_exact_number), _exact_bindings(ex.args[2])))
    return ex
end

_exact_number(v::Union{Integer, Rational}) = v isa Bool ? v : convert(GiacExpr, v)
_exact_number(v) = v
