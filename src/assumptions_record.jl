# assumptions(x): what GIAC assumes of a variable, as a structured record.
#
# GIAC's `about(x)` returns `x` for a free variable, the value of an assigned one, or an
# assumption record printed as `assume[integer,[line[2,+infinity]],[2]]`: a domain (`[]` for
# none), a union of intervals `line[a,b]`, and the points excluded from them, which make the
# matching ends open. MathInterchange's feedback (point 6) asked for this as data, so callers can
# check that every premise reached GIAC.

"""
    Giac.Assumptions

What GIAC assumes of a variable, as returned by [`assumptions`](@ref):

* `domain`: `:real`, `:integer`, `:complex`, `:rational`, … or `nothing`;
* `intervals`: the union of intervals the variable lies in, each a named tuple
  `(lo, hi, lo_closed, hi_closed)` whose ends are `GiacExpr`s (`-infinity` and `+infinity`
  ends are open); empty when GIAC records no range;
* `excluded`: the points GIAC excludes, as it records them (they open the matching ends);
* `value`: the value of an assigned variable, or `nothing`;
* `raw`: GIAC's own `about(x)`, kept as evidence.
"""
struct Assumptions
    domain::Union{Nothing, Symbol}
    intervals::Vector{NamedTuple{(:lo, :hi, :lo_closed, :hi_closed), Tuple{GiacExpr, GiacExpr, Bool, Bool}}}
    excluded::Vector{GiacExpr}
    value::Union{Nothing, GiacExpr}
    raw::GiacExpr
end

"Whether nothing is assumed of the variable and it holds no value."
Base.isempty(a::Assumptions) =
    a.domain === nothing && isempty(a.intervals) && isempty(a.excluded) && a.value === nothing

# `Assumptions(integer, [2, +infinity[)`: the domain, then the union of intervals
function Base.show(io::IO, a::Assumptions)
    parts = String[]
    a.domain === nothing || push!(parts, string(a.domain))
    isempty(a.intervals) || push!(parts, join((string(i.lo_closed ? "[" : "]", i.lo, ", ", i.hi,
                                                      i.hi_closed ? "]" : "[") for i in a.intervals), " ∪ "))
    a.value === nothing || push!(parts, "value $(a.value)")
    print(io, "Assumptions(", isempty(parts) ? "none" : join(parts, ", "), ")")
end

# An assumption record is a vector `assume[...]` whose first element is the domain.
_is_assume_record(r::GiacExpr) = is_vector(r) && startswith(string(r), "assume[")

_infinite(e::GiacExpr) = (s = string(e); s == "+infinity" || s == "-infinity" || s == "infinity")

"""
    assumptions(x::GiacExpr) -> Giac.Assumptions

What GIAC assumes of the variable `x`, read from `about(x)`: its domain, the union of intervals
it lies in (with open or closed ends), the excluded points, or its value if it is assigned. The
record holds only what reached GIAC: a condition GIAC does not keep, such as `x != 3`, does not
appear, which lets a caller check its premises against it.

```julia
@giac_var a
Giac.Commands.assume((a > 0) & (a <= 10))
assumptions(a)              # Assumptions(]0, 10])
assumptions(a).intervals    # [(lo = 0, hi = 10, lo_closed = false, hi_closed = true)]
```
"""
function assumptions(x::GiacExpr)
    raw = Commands.about(x)
    if !_is_assume_record(raw)
        # a free variable is its own name; anything else is the value it was assigned
        free = isequal(string(raw), string(x))
        return Assumptions(nothing, [], GiacExpr[], free ? nothing : raw, raw)
    end
    parts = collect(GiacExpr, raw)
    d = string(parts[1])
    domain = d == "[]" ? nothing : Symbol(d)
    lines = length(parts) >= 2 ? collect(GiacExpr, parts[2]) : GiacExpr[]
    excluded = length(parts) >= 3 ? collect(GiacExpr, parts[3]) : GiacExpr[]
    excluded_names = Set(string.(excluded))
    open_end(e) = _infinite(e) || string(e) in excluded_names
    intervals = map(lines) do l
        lo, hi = collect(GiacExpr, l)
        (lo = lo, hi = hi, lo_closed = !open_end(lo), hi_closed = !open_end(hi))
    end
    return Assumptions(domain, intervals, excluded, nothing, raw)
end
